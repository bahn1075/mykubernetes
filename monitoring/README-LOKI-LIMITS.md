# "Too Many Open Files" 완전 해결 가이드

## 문제 상황

k9s에서 pod 로그를 볼 때 다음 에러 발생:
- `too many open files`
- `stream EOF`
- `failed to create fsnotify watcher: too many open files`
- 로그가 tail -f처럼 갱신되지 않고 중단됨

## 원인

### 1. Loki의 동시 tail 요청 문제
Loki가 로그 스트림을 처리할 때 많은 파일 디스크립터를 사용하는데, 특히:
- **동시 tail 요청**이 많을 때
- **긴 시간 범위** 쿼리 시
- **여러 pod 로그**를 동시에 조회할 때

### 2. Node Exporter의 fsnotify watcher 문제 ⭐
**주요 원인:** node-exporter의 **textfile collector**가 파일시스템 변경사항을 모니터링하기 위해 fsnotify watcher를 생성할 때 파일 디스크립터를 과도하게 사용

에러 메시지:
```
failed to create fsnotify watcher: too many open files
stream closed: EOF for monitoring/prometheus-prometheus-node-exporter-4ss94 (node-exporter)
```

## 해결 방법

### 1. Loki 제한 설정 추가

`loki-values.yaml`에 다음 설정 추가됨:

```yaml
loki:
  limits_config:
    max_concurrent_tail_requests: 20     # 동시 tail 요청 제한 (핵심!)
    max_entries_limit_per_query: 10000   # 쿼리당 최대 엔트리
    split_queries_by_interval: 30m       # 쿼리를 30분 단위로 분할
```

**핵심 설정:**
- `max_concurrent_tail_requests: 20`: 동시에 처리할 수 있는 tail 요청을 20개로 제한
  - k9s로 여러 pod 로그를 동시에 보거나, 여러 사용자가 동시에 조회할 때 보호
  - 기본값보다 낮게 설정하여 파일 디스크립터 소진 방지

### 2. Node Exporter textfile collector 비활성화 (완료) ⭐

**핵심 해결책:** `prometheus-values.yaml`에 다음 설정 추가:

```yaml
nodeExporter:
  enabled: true
  # fsnotify watcher 에러 방지 설정
  extraArgs:
    - --collector.disable-defaults
    - --collector.cpu
    - --collector.meminfo
    - --collector.diskstats
    - --collector.filesystem
    - --collector.loadavg
    - --collector.netdev
    - --collector.netstat
    - --collector.uname
    - --collector.vmstat
    - --no-collector.textfile  # textfile collector 비활성화 (핵심!)
  hostNetwork: true
  hostPID: true
  hostRootFsMount:
    enabled: true
    mountPropagation: HostToContainer
```

**왜 이렇게?**
- `--no-collector.textfile`: textfile collector를 완전히 비활성화
  - textfile collector는 `/var/lib/node_exporter/textfile_collector` 디렉토리의 파일 변경을 fsnotify로 감시
  - 이 과정에서 많은 파일 디스크립터를 사용하여 "too many open files" 에러 발생
- 필요한 collector만 명시적으로 활성화 (cpu, memory, disk, network 등)
- textfile collector 없이도 기본 시스템 메트릭은 모두 수집 가능

### 3. 적용 방법

```bash
cd /app/mykubernetes/monitoring
helm upgrade loki grafana/loki -n monitoring -f loki-values.yaml
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -w
```

### 3. 확인 방법

```bash
# Loki pod 상태 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Loki 로그에서 에러 확인
kubectl logs -n monitoring loki-0 -c loki --tail=50

# 파일 디스크립터 사용량 확인
kubectl exec -n monitoring loki-0 -c loki -- sh -c 'ls -la /proc/1/fd | wc -l'
```

## k9s 사용 팁

### 1. 로그 조회 시 주의사항
- 너무 많은 pod 로그를 동시에 열지 않기
- 로그 버퍼 크기 조정: k9s에서 `:xray logs` 명령으로 설정 확인

### 2. k9s 설정 최적화

`~/.config/k9s/config.yml`:
```yaml
k9s:
  logger:
    tail: 200            # tail 라인 수 줄이기
    buffer: 5000         # 버퍼 크기
  refreshRate: 2         # 화면 갱신 주기 (초)
```

### 3. 대안: kubectl 직접 사용

k9s 대신 kubectl로 로그 조회:
```bash
# 특정 pod 로그 tail
kubectl logs -f -n namespace pod-name --tail=100

# 여러 pod 로그 (라벨 셀렉터)
kubectl logs -f -n namespace -l app=myapp --tail=50 --max-log-requests=5
```

## 모니터링

### Grafana에서 Loki 메트릭 확인

1. Grafana 접속
2. Explore → Prometheus 선택
3. 다음 쿼리 실행:

```promql
# Loki tail 요청 수
loki_request_duration_seconds_count{route="loki_api_v1_tail"}

# 파일 디스크립터 사용량 (Loki pod)
process_open_fds{job="loki"}

# 최대 파일 디스크립터
process_max_fds{job="loki"}
```

## 추가 최적화 (필요시)

더 강력한 제한이 필요한 경우:

```yaml
loki:
  limits_config:
    max_concurrent_tail_requests: 10    # 더 낮게 설정
    max_streams_per_user: 10000         # 사용자당 최대 스트림
    max_query_parallelism: 16           # 쿼리 병렬 처리 제한
    max_query_series: 500               # 쿼리당 최대 시리즈
```

## 참고

- [Loki Limits Config 문서](https://grafana.com/docs/loki/latest/configuration/#limits_config)
- 현재 설정: `max_concurrent_tail_requests: 20`
- 적용 날짜: 2025-11-24
