# brincando-tr069
## Instala e configura o GenieACS com proxy reverso(NGINX).

Este script instala no modo all-in-one o GenieACS com o NGINX como proxy reverso e HTTPS para o módulo UI.
Ele é um compilado da doc oficial https://docs.genieacs.com/en/latest/ e de outros sites como https://blog.remontti.com.br/.
Não garanto que esteja pronto para usar em produção, mas dá pra brincar! :)

Os módulos foram configurados para responder somente em localhost e por causa do reverse proxy as "portas-padrão", trocadas para responderem no NGINX.


### Portas configuradas para os módulo do GenieACS

- GenieACS UI: 127.0.0.1:3000
- GenieACS CWMP: 127.0.0.1:3001
- GenieACS NBI: 127.0.0.1:3002
- GenieACS UI: 127.0.0.1:3003

### Portas configuradas para NGINX
- NGINX porta 3000, redireciona para 127.0.0.1:3000(UI)
- NGINX porta 7547, redireciona para 127.0.0.1:3001(CWMP)
- NGINX porta 7557, redireciona para 127.0.0.1:3002(NBI)
- NGINX porta 7567, redireciona para 127.0.0.1:3003(FS)

### O script foi testado no seguinte cenário:
  - mongodb 5.0
  - Debian 11 (bullseye)
  - Proxmox 6.3-2, cpu=host
  - NodeJS 18.x LTS

Ao final, deverás ter algo parecido com isso:

![asdas](https://raw.githubusercontent.com/ojpojao/brincando-tr069/main/setup_genieacs.png)
