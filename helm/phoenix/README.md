# Phoenix Deployment

## Install

```bash
helm upgrade --install phoenix oci://registry-1.docker.io/arizephoenix/phoenix-helm \
  -f values.yaml \
  -n phoenix \
  --create-namespace
```

## Uninstall

```bash
helm uninstall phoenix -n phoenix
```

## Access

- URL: http://phoenix.64bit.kr
- Email: admin@localhost
- Password: admin
