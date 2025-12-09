-- @pgsql Chat Query Editor (158.180.71.148)

-- phoenix 유저 생성
CREATE USER phoenix WITH PASSWORD 'Thinq20airecipe!';

-- phoenix 데이터베이스에 대한 연결 권한
GRANT CONNECT ON DATABASE phoenix TO phoenix;

-- phoenix 전용 스키마 생성 (소유자: phoenix)
CREATE SCHEMA IF NOT EXISTS phoenix AUTHORIZATION phoenix;

-- phoenix 스키마를 기본 검색 경로로 설정
ALTER USER phoenix SET search_path TO phoenix;
