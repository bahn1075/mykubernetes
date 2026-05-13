import os
import re
import tempfile
import zipfile
from copy import deepcopy
from difflib import get_close_matches
from pathlib import Path
from typing import TYPE_CHECKING, Any

from typing_extensions import override

from lfx.base.vectorstores.model import LCVectorStoreComponent, check_cached_vector_store
from lfx.base.data.storage_utils import parse_storage_path
from lfx.services.deps import get_settings_service, get_storage_service
from lfx.utils.async_helpers import run_until_complete
from lfx.inputs.inputs import BoolInput, DropdownInput, HandleInput, IntInput, SecretStrInput, StrInput
from lfx.io import FileInput
from lfx.schema.data import Data

if TYPE_CHECKING:
    from langchain_community.vectorstores.oraclevs import OracleVS
    from lfx.schema.dataframe import DataFrame


class OracleDatabaseVectorStoreComponent(LCVectorStoreComponent):
    """Oracle Database 23ai vector store with search capabilities."""

    display_name: str = "Oracle Database Vector Store"
    description: str = "Oracle 23ai Vector Store with local embeddings and configurable retrieval"
    name = "OracleDBVector"
    icon = "Oracle"

    inputs = [
        StrInput(
            name="db_user",
            display_name="Database User",
            info="Oracle database username (e.g., ADMIN)",
        ),
        SecretStrInput(
            name="db_password",
            display_name="Database Password",
            info="Oracle database password",
        ),
        StrInput(
            name="dsn",
            display_name="DSN",
            info="Database connection string (e.g., CA4X9LQR5QLMO4EB_high)",
        ),
        FileInput(
            name="wallet_file",
            display_name="Wallet ZIP File",
            info="Upload Oracle wallet ZIP file",
            file_types=["zip"],
            real_time_refresh=True,
        ),
        SecretStrInput(
            name="wallet_password",
            display_name="Wallet Password",
            info="Oracle wallet password",
        ),
        StrInput(
            name="table_name",
            display_name="Table Name",
            info="Vector table name (e.g., PDFCOLLECTION)",
            value="PDFCOLLECTION",
        ),
        *LCVectorStoreComponent.inputs,
        HandleInput(
            name="embedding",
            display_name="Embedding Model",
            input_types=["Embeddings"],
        ),
        IntInput(
            name="embedding_dimension",
            display_name="Embedding Dimension",
            info="Vector dimension for the embedding model. Leave 0 to auto-detect from the connected embedding model.",
            advanced=True,
            value=0,
        ),
        DropdownInput(
            name="distance_strategy",
            display_name="Distance Strategy",
            options=["COSINE", "EUCLIDEAN_DISTANCE", "DOT_PRODUCT"],
            value="COSINE",
            advanced=True,
        ),
        BoolInput(
            name="allow_duplicates",
            display_name="Allow Duplicates",
            advanced=True,
            value=False,
            info="If false, will not add documents that are already in the Vector Store.",
        ),
        DropdownInput(
            name="search_type",
            display_name="Search Type",
            options=["Similarity", "MMR"],
            value="Similarity",
            advanced=True,
        ),
        IntInput(
            name="number_of_results",
            display_name="Number of Results",
            info="Number of results to return.",
            advanced=True,
            value=10,
        ),
        IntInput(
            name="limit",
            display_name="Limit",
            advanced=True,
            info="Limit the number of records to compare when Allow Duplicates is False.",
        ),
        IntInput(
            name="add_batch_size",
            display_name="Add Batch Size",
            advanced=True,
            info="Number of documents to embed and insert per batch. Lower this if the embedding server fails on large batches.",
            value=8,
        ),
        IntInput(
            name="max_document_chars",
            display_name="Max Document Characters",
            advanced=True,
            info="Split documents longer than this before embedding. Use 0 to disable this extra split.",
            value=2000,
        ),
    ]

    def _clean_metadata(self, metadata):
        """Clean metadata to ensure JSON serializability."""
        import json

        if not metadata:
            return {}

        cleaned = {}
        for key, value in metadata.items():
            try:
                json.dumps(value)
                cleaned[key] = value
            except (TypeError, ValueError):
                cleaned[key] = str(value)

        return cleaned

    def _extract_wallet_file_path(self, wallet_file: Any) -> str:
        """Return a file path from the shapes Langflow FileInput can emit."""
        if isinstance(wallet_file, list):
            wallet_file = wallet_file[0] if wallet_file else None

        if isinstance(wallet_file, dict):
            wallet_file = wallet_file.get("file_path") or wallet_file.get("path") or wallet_file.get("value")

        if isinstance(wallet_file, list):
            wallet_file = wallet_file[0] if wallet_file else None

        if not wallet_file:
            raise ValueError("Wallet file is required")

        return str(wallet_file)

    def _wallet_file_value(self, template: dict) -> str:
        """Return the currently selected wallet path from a Langflow template/build config."""
        wallet_input = template.get("wallet_file", {})
        file_path = wallet_input.get("file_path")
        value = file_path if file_path else wallet_input.get("value")
        return self._extract_wallet_file_path(value) if value else ""

    def update_build_config(self, build_config: dict, field_value: Any, field_name: str | None = None) -> dict:
        """Refresh the wallet file field so selecting a ZIP gives immediate UI feedback."""
        if field_name == "wallet_file" and "wallet_file" in build_config:
            wallet_input = build_config["wallet_file"]
            wallet_path = self._wallet_file_value(build_config)
            if not wallet_path and field_value:
                wallet_path = self._extract_wallet_file_path(field_value)
            wallet_input["value"] = wallet_path
            if not wallet_input.get("file_path"):
                wallet_input["file_path"] = wallet_path
            wallet_input["info"] = (
                f"Selected wallet ZIP file: {Path(wallet_path).name}"
                if wallet_path
                else "Upload Oracle wallet ZIP file"
            )
        return build_config

    def _get_wallet_file_path(self) -> str:
        """업로드된 wallet 파일의 로컬 경로를 가져옵니다. S3 storage인 경우 임시 파일로 다운로드합니다."""
        wallet_file = self._extract_wallet_file_path(self.wallet_file)
        
        settings = get_settings_service().settings
        
        # Local storage: 파일 경로를 그대로 사용
        if settings.storage_type == "local":
            if not os.path.exists(wallet_file):
                raise FileNotFoundError(f"Wallet file not found: {wallet_file}")
            return wallet_file
        
        # S3 storage: 파일을 임시 위치로 다운로드
        parsed = parse_storage_path(wallet_file)
        if not parsed:
            raise ValueError(f"Invalid S3 path format: {wallet_file}. Expected 'flow_id/filename'")
        
        storage_service = get_storage_service()
        flow_id, filename = parsed
        
        # S3에서 파일 내용 가져오기
        content = run_until_complete(storage_service.get_file(flow_id, filename))
        
        # 임시 파일로 저장
        suffix = Path(filename).suffix
        temp_file = tempfile.NamedTemporaryFile(mode="wb", suffix=suffix, delete=False)
        try:
            temp_file.write(content)
            temp_file.flush()
            temp_path = temp_file.name
        finally:
            temp_file.close()
        
        self.log(f"Downloaded wallet file from S3 to: {temp_path}")
        return temp_path

    def _get_tns_aliases(self, wallet_dir: str) -> list[str]:
        """Return service aliases declared in the wallet tnsnames.ora file."""
        tnsnames_path = Path(wallet_dir) / "tnsnames.ora"
        if not tnsnames_path.exists():
            raise FileNotFoundError(f"tnsnames.ora not found in wallet directory: {wallet_dir}")

        aliases = []
        for line in tnsnames_path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = re.match(r"^\s*([A-Za-z0-9_.-]+)\s*=", line)
            if match:
                aliases.append(match.group(1))
        return aliases

    def _validate_dsn_alias(self, wallet_dir: str) -> str:
        """Validate the requested DSN against tnsnames.ora and return the wallet alias casing."""
        dsn = str(self.dsn or "").strip()
        if not dsn:
            raise ValueError("DSN is required")

        aliases = self._get_tns_aliases(wallet_dir)
        alias_map = {alias.lower(): alias for alias in aliases}
        if dsn.lower() in alias_map:
            return alias_map[dsn.lower()]

        normalized_dsn = dsn.replace(".", "_").lower()
        suggestion = alias_map.get(normalized_dsn)
        if suggestion is None:
            matches = get_close_matches(normalized_dsn, alias_map.keys(), n=1, cutoff=0.6)
            suggestion = alias_map[matches[0]] if matches else None

        aliases_text = ", ".join(aliases) if aliases else "(none)"
        hint = f" Did you mean '{suggestion}'?" if suggestion else ""
        raise ValueError(
            f"DSN '{dsn}' was not found in wallet tnsnames.ora.{hint} Available DSN aliases: {aliases_text}"
        )

    def _get_embedding_dimension(self) -> int:
        """Return the vector dimension expected by the configured embedding model."""
        configured_dimension = int(getattr(self, "embedding_dimension", 0) or 0)
        if configured_dimension > 0:
            return configured_dimension

        if self.embedding is None:
            raise ValueError("Embedding model is required to auto-detect vector dimension")

        if not hasattr(self.embedding, "embed_query"):
            raise TypeError("Embedding model must provide an embed_query method to auto-detect vector dimension")

        sample_embedding = self.embedding.embed_query("dimension probe")
        dimension = len(sample_embedding)
        if dimension <= 0:
            raise ValueError("Embedding model returned an empty vector while detecting dimension")

        self.log(f"Auto-detected embedding dimension: {dimension}")
        return dimension

    def _get_add_batch_size(self) -> int:
        """Return the document batch size for embedding and inserting documents."""
        return max(1, int(getattr(self, "add_batch_size", 8) or 8))

    def _get_max_document_chars(self) -> int:
        """Return the maximum document text length to send to the embedding model."""
        return max(0, int(getattr(self, "max_document_chars", 2000) or 0))

    def _split_long_documents(self, documents: list) -> list:
        """Split very long documents before embedding to avoid unstable embedding responses."""
        max_chars = self._get_max_document_chars()
        if max_chars <= 0:
            return documents

        split_documents = []
        for doc in documents:
            text = doc.page_content or ""
            if len(text) <= max_chars:
                split_documents.append(doc)
                continue

            overlap = min(200, max_chars // 5)
            step = max(1, max_chars - overlap)
            part_count = 0
            for start in range(0, len(text), step):
                chunk = text[start : start + max_chars]
                if not chunk:
                    continue
                new_doc = deepcopy(doc)
                new_doc.page_content = chunk
                new_doc.metadata = dict(new_doc.metadata or {})
                new_doc.metadata["split_part"] = part_count
                new_doc.metadata["split_source_length"] = len(text)
                split_documents.append(new_doc)
                part_count += 1

            self.log(f"Split long document of {len(text)} chars into {part_count} parts.")

        return split_documents

    def _is_nan_embedding_error(self, error: Exception) -> bool:
        """Return True when Ollama failed to encode an embedding response containing NaN."""
        error_text = str(error).lower()
        return "unsupported value: nan" in error_text or "unsupported value: null" in error_text

    def _document_preview(self, doc) -> str:
        """Return a compact document preview for actionable embedding errors."""
        text = (doc.page_content or "").replace("\n", "\\n")
        return text[:300]

    def _add_documents_with_retry(
        self,
        vector_store: "OracleVS",
        documents: list,
        *,
        start_number: int,
        total: int,
    ) -> None:
        """Add documents, splitting failed NaN batches until the offending text is isolated."""
        if not documents:
            return

        try:
            vector_store.add_documents(documents)
            end_number = start_number + len(documents) - 1
            self.log(f"Added document batch {start_number}-{end_number} of {total}.")
            return
        except Exception as e:
            if not self._is_nan_embedding_error(e):
                raise

            end_number = start_number + len(documents) - 1
            self.log(f"Embedding returned NaN for documents {start_number}-{end_number}; retrying smaller chunks.")

            if len(documents) > 1:
                midpoint = len(documents) // 2
                self._add_documents_with_retry(
                    vector_store,
                    documents[:midpoint],
                    start_number=start_number,
                    total=total,
                )
                self._add_documents_with_retry(
                    vector_store,
                    documents[midpoint:],
                    start_number=start_number + midpoint,
                    total=total,
                )
                return

            doc = documents[0]
            text = doc.page_content or ""
            if len(text) > 500:
                midpoint = len(text) // 2
                split_docs = []
                for part_number, chunk in enumerate((text[:midpoint], text[midpoint:])):
                    new_doc = deepcopy(doc)
                    new_doc.page_content = chunk
                    new_doc.metadata = dict(new_doc.metadata or {})
                    new_doc.metadata["retry_split_part"] = part_number
                    new_doc.metadata["retry_split_source_length"] = len(text)
                    split_docs.append(new_doc)

                self.log(
                    f"Splitting document {start_number} from {len(text)} chars into smaller retry chunks."
                )
                self._add_documents_with_retry(
                    vector_store,
                    split_docs,
                    start_number=start_number,
                    total=total,
                )
                return

            msg = (
                "Embedding server returned NaN for a single short document "
                f"at position {start_number} of {total}. "
                f"Document preview: {self._document_preview(doc)}"
            )
            self.log(msg)
            raise ValueError(msg) from e

    def _oracle_table_to_data(self, conn, table_name: str, limit: int | None = None) -> list[Data]:
        """Oracle 테이블에서 데이터를 가져와 Data 객체 리스트로 변환합니다 (ChromaDB의 chroma_collection_to_data와 유사)."""
        try:
            cursor = conn.cursor()
            
            # Limit 적용하여 쿼리 실행
            if limit:
                query = f"SELECT ID, TEXT, METADATA FROM {table_name} WHERE ROWNUM <= :limit"
                cursor.execute(query, {"limit": limit})
            else:
                query = f"SELECT ID, TEXT, METADATA FROM {table_name}"
                cursor.execute(query)
            
            rows = cursor.fetchall()
            cursor.close()
            
            data_list = []
            for row in rows:
                doc_id, text, metadata_json = row
                
                # metadata JSON 파싱
                metadata = {}
                if metadata_json:
                    import json
                    try:
                        metadata = json.loads(metadata_json)
                    except json.JSONDecodeError:
                        metadata = {}
                
                data = Data(
                    id=doc_id,
                    text=text,
                    data=metadata,
                )
                data_list.append(data)
            
            return data_list
            
        except Exception as e:
            self.log(f"Failed to fetch data from Oracle table: {str(e)}")
            return []

    @override
    @check_cached_vector_store
    def build_vector_store(self) -> "OracleVS":
        """Builds the Oracle Vector Store object."""
        try:
            import oracledb
            from langchain_community.vectorstores.oraclevs import OracleVS
            from langchain_community.vectorstores.utils import DistanceStrategy
        except ImportError as e:
            msg = "Could not import required packages."
            raise ImportError(msg) from e

        # wallet zip 파일 경로 가져오기 (로컬 또는 S3에서 다운로드)
        wallet_file_path = None
        temp_wallet_dir = None
        temp_downloaded_wallet = None
        
        try:
            wallet_file_path = self._get_wallet_file_path()
            
            # S3에서 다운로드한 경우 나중에
            settings = get_settings_service().settings
            if settings.storage_type == "s3":
                temp_downloaded_wallet = wallet_file_path
            
            # 임시 디렉토리 생성 및 zip 파일 압축 해제
            temp_wallet_dir = tempfile.mkdtemp(prefix="oracle_wallet_")
            self.log(f"Extracting wallet to temporary directory: {temp_wallet_dir}")
            
            with zipfile.ZipFile(wallet_file_path, 'r') as zip_ref:
                zip_ref.extractall(temp_wallet_dir)
            
            self.log(f"Wallet extracted successfully")
            
        except Exception as e:
            # 실패 시 임시 파일들 정리
            if temp_wallet_dir and os.path.exists(temp_wallet_dir):
                import shutil
                shutil.rmtree(temp_wallet_dir, ignore_errors=True)
            if temp_downloaded_wallet and os.path.exists(temp_downloaded_wallet):
                os.unlink(temp_downloaded_wallet)
            error_msg = f"Failed to extract wallet file: {str(e)}"
            self.status = error_msg
            raise RuntimeError(error_msg) from e
        finally:
            # S3에서 다운로드한 임시 wallet 파일 정리
            if temp_downloaded_wallet and os.path.exists(temp_downloaded_wallet):
                try:
                    os.unlink(temp_downloaded_wallet)
                except Exception:
                    pass

        connect_args = {
            "user": self.db_user,
            "password": self.db_password,
            "dsn": self._validate_dsn_alias(temp_wallet_dir),
            "config_dir": temp_wallet_dir,
            "wallet_location": temp_wallet_dir,
            "wallet_password": self.wallet_password,
        }

        try:
            conn = oracledb.connect(**connect_args)
            self.log(f"Connected to Oracle Database: {self.dsn}")
        except Exception as e:
            # 연결 실패 시 임시 디렉토리 정리
            if temp_wallet_dir and os.path.exists(temp_wallet_dir):
                import shutil
                shutil.rmtree(temp_wallet_dir, ignore_errors=True)
            error_msg = f"Failed to connect to Oracle Database: {str(e)}"
            self.status = error_msg
            raise ConnectionError(error_msg) from e

        try:
            cursor = conn.cursor()
            embedding_dimension = self._get_embedding_dimension()
            cursor.execute(
                "SELECT table_name FROM user_tables WHERE UPPER(table_name) = UPPER(:table_name)",
                {"table_name": self.table_name},
            )
            row = cursor.fetchone()

            if not row:
                # 테이블이 존재하지 않으면 생성
                self.log(f"Table '{self.table_name}' does not exist. Creating table...")
                try:
                    # 테이블 생성 SQL
                    create_table_sql = f"""
                    CREATE TABLE {self.db_user}.{self.table_name} (
                        ID VARCHAR2(100 BYTE),
                        TEXT CLOB,
                        METADATA CLOB,
                        EMBEDDING VECTOR({embedding_dimension}, *),
                        CREATED_AT TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP
                    )
                    """
                    cursor.execute(create_table_sql)
                    self.log(
                        f"Table '{self.table_name}' created successfully with vector dimension {embedding_dimension}"
                    )
                    
                    # Primary Key 추가
                    pk_sql = f"""
                    ALTER TABLE {self.db_user}.{self.table_name} ADD PRIMARY KEY (ID)
                    USING INDEX PCTFREE 10 INITRANS 20 MAXTRANS 255
                    TABLESPACE DATA ENABLE
                    """
                    cursor.execute(pk_sql)
                    self.log(f"Primary key added to '{self.table_name}'")
                    
                    # Vector 인덱스 생성
                    index_sql = f"""
                    CREATE VECTOR INDEX {self.db_user}.VECTOR_IDX_{self.table_name} ON {self.db_user}.{self.table_name} (EMBEDDING)
                    ORGANIZATION INMEMORY NEIGHBOR GRAPH
                    WITH DISTANCE COSINE
                    WITH TARGET ACCURACY 95
                    """
                    cursor.execute(index_sql)
                    self.log(f"Vector index created for '{self.table_name}'")
                    
                    conn.commit()
                    actual_table_name = self.table_name
                except Exception as create_error:
                    conn.rollback()
                    cursor.close()
                    error_msg = f"Failed to create table '{self.table_name}': {str(create_error)}"
                    self.status = error_msg
                    raise RuntimeError(error_msg) from create_error
            else:
                actual_table_name = row[0]
                self.log(f"Found existing table: {actual_table_name}")
            
            cursor.close()
        except Exception as e:
            error_msg = f"Failed to validate or create table: {str(e)}"
            self.status = error_msg
            raise RuntimeError(error_msg) from e

        ds_map = {
            "COSINE": DistanceStrategy.COSINE,
            "EUCLIDEAN_DISTANCE": DistanceStrategy.EUCLIDEAN_DISTANCE,
            "DOT_PRODUCT": DistanceStrategy.DOT_PRODUCT,
        }
        distance = ds_map.get(self.distance_strategy, DistanceStrategy.COSINE)

        oracle_store = OracleVS(
            client=conn,
            table_name=actual_table_name,
            distance_strategy=distance,
            embedding_function=self.embedding,
        )

        self.log(f"Created OracleVS instance for table: {actual_table_name}")

        # ChromaDB 스타일: 문서 추가를 별도 메서드로 분리
        self._add_documents_to_vector_store(oracle_store, conn, actual_table_name)
        
        # ChromaDB 스타일: 상태 업데이트
        limit = int(self.limit) if self.limit is not None and str(self.limit).strip() else None
        self.status = self._oracle_table_to_data(conn, actual_table_name, limit=limit)
        
        return oracle_store

    def _add_documents_to_vector_store(self, vector_store: "OracleVS", conn, table_name: str) -> None:
        """Adds documents to the Vector Store (ChromaDB 스타일)."""
        ingest_data: list | Data | "DataFrame" = self.ingest_data
        if not ingest_data:
            self.status = ""
            return

        # Convert DataFrame to Data if needed using parent's method
        ingest_data = self._prepare_ingest_data()

        stored_documents_without_id = []
        if self.allow_duplicates:
            stored_data = []
        else:
            limit = int(self.limit) if self.limit is not None and str(self.limit).strip() else None
            stored_data = self._oracle_table_to_data(conn, table_name, limit=limit)
            for value in deepcopy(stored_data):
                # ID 제거하여 텍스트/메타데이터만으로 비교 (ChromaDB와 동일한 방식)
                del value.id
                stored_documents_without_id.append(value)

        documents = []
        for _input in ingest_data or []:
            if isinstance(_input, Data):
                # ChromaDB 스타일: 중복 체크
                if _input not in stored_documents_without_id:
                    doc = _input.to_lc_document()
                    doc.metadata = self._clean_metadata(doc.metadata)
                    documents.append(doc)
            else:
                msg = "Vector Store Inputs must be Data objects."
                raise TypeError(msg)

        if documents and self.embedding is not None:
            documents = self._split_long_documents(documents)
            batch_size = self._get_add_batch_size()
            self.log(f"Adding {len(documents)} documents to the Vector Store in batches of {batch_size}.")
            for start in range(0, len(documents), batch_size):
                batch = documents[start : start + batch_size]
                try:
                    self._add_documents_with_retry(
                        vector_store,
                        batch,
                        start_number=start + 1,
                        total=len(documents),
                    )
                except Exception as e:
                    error_text = str(e)
                    if "ORA-51803" in error_text:
                        msg = (
                            "Embedding vector dimension does not match the Oracle table definition. "
                            "Create a new table or drop/recreate the existing table after changing embedding models."
                        )
                        self.log(msg)
                        raise ValueError(msg) from e
                    if self._is_nan_embedding_error(e):
                        msg = (
                            "Embedding server returned NaN while embedding documents "
                            f"{start + 1}-{start + len(batch)} of {len(documents)}. "
                            "The batch was retried down to a smaller chunk, but Ollama still returned an invalid "
                            "embedding response. Lower Max Document Characters or use a more stable embedding model."
                        )
                        self.log(msg)
                        raise ValueError(msg) from e
                    self.log(f"Warning: Failed to add document batch {start + 1}-{start + len(batch)}: {error_text}")
                    raise
        else:
            self.log("No documents to add to the Vector Store.")
