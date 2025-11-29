printf "%-12s %-20s %-12s %-18s %-20s %-16s %-16s %-18s\n" "CONTAINER_ID" "NAME" "STATUS" "CREATED" "NETWORK" "IP" "GATEWAY" "MAC"; \
docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.RunningFor}}" | tail -n +2 | \
while read cid name status created; do \
  docker inspect --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}|{{.IPAddress}}|{{.Gateway}}|{{.MacAddress}}{{"\n"}}{{end}}' "$cid" 2>/dev/null | \
  grep -v '^$' | \
  while IFS='|' read net ip gw mac; do \
    [ -z "$net" ] && net="(none)" ip="(none)" gw="(none)" mac="(none)"; \
    printf "%-12s %-20s %-12s %-18s %-20s %-16s %-16s %-18s\n" "${cid:0:12}" "$name" "$status" "$created" "$net" "$ip" "$gw" "$mac"; \
  done; \
  docker inspect --format '{{.NetworkSettings.Networks}}' "$cid" 2>/dev/null | grep -q "map\\[" || \
    printf "%-12s %-20s %-12s %-18s %-20s %-16s %-16s %-18s\n" "${cid:0:12}" "$name" "$status" "$created" "(none)" "(none)" "(none)" "(none)"; \
  echo ""; \
done

printf "%-20s %-12s %-10s %-18s %-18s\n" "NETWORK" "DRIVER" "SCOPE" "SUBNET" "GATEWAY"; \
docker network ls --format "{{.Name}}\t{{.Driver}}\t{{.Scope}}" | \
while IFS=$'\t' read name driver scope; do \
  docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}|{{.Gateway}}{{"\n"}}{{end}}' "$name" 2>/dev/null | \
  grep -v '^$' | \
  while IFS='|' read subnet gateway; do \
    [ -z "$subnet" ] && subnet="(none)" gateway="(none)"; \
    printf "%-20s %-12s %-10s %-18s %-18s\n" "$name" "$driver" "$scope" "$subnet" "$gateway"; \
  done; \
  docker network inspect --format '{{len .IPAM.Config}}' "$name" 2>/dev/null | grep -q '0' && \
    printf "%-20s %-12s %-10s %-18s %-18s\n" "$name" "$driver" "$scope" "(none)" "(none)"; \
done
