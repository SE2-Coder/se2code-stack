# ⚡ se2Code Stack Server

> **Suite Profesional de Infraestructura y Despliegue Automatizado**  
> Diseñada para máxima velocidad, alta concurrencia en WordPress, Landing Pages ultrarrápidas y seguridad empresarial.

[![Engineering Hub](https://img.shields.io/badge/Engineering_Hub-se2code.engineer-00d2ff?style=for-the-badge&logo=codeforces&logoColor=white)](https://se2code.engineer)
[![Agency Services](https://img.shields.io/badge/Commercial_Services-se2code.com-7928CA?style=for-the-badge&logo=googlecloud&logoColor=white)](https://se2code.com)
[![Docker](https://img.shields.io/badge/Docker_29+-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-success?style=for-the-badge)](LICENSE)

---

## 🚀 Instalación en 1 Solo Comando (Estilo CyberPanel / Coolify)

Para desplegar todo el stack en un servidor virgen (**Probado oficialmente en Debian 12 y Debian 13**), entra por SSH como `root` y pega este comando único:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/SE2-Coder/se2code-stack/main/install.sh)
```

*(O si prefieres el método de tubería tradicional)*:
```bash
curl -sSL https://raw.githubusercontent.com/SE2-Coder/se2code-stack/main/install.sh | bash
```

### ¿Qué hace este comando automáticamente?
1. 🔍 **Prepara el sistema**: Instala silenciosamente `git`, `curl` y certificados seguros si no están presentes.
2. 📦 **Descarga el stack**: Clona la versión optimizada en `/opt/se2code-stack`.
3. 📊 **Diagnostica el hardware**: Evalúa núcleos de CPU, RAM libre, Swap y disco, calculando cuántos WordPress soporta el servidor de forma segura.
4. 🛡️ **Protege la memoria**: Si detecta menos de 1 GB de Swap, te ofrece crear automáticamente un archivo Swap de 2 GB (`swappiness=10`) para prevenir caídas por Out-Of-Memory (OOM).
5. 🐳 **Instala Docker Engine y Compose**: Configura la última versión oficial de Docker y el firewall UFW.
6. 🎯 **Asistente interactivo**: Te pregunta qué módulos deseas activar (**WordPress**, **WireGuard VPN** o **Ambos**).
7. 🌐 **Aprovisiona sitios**: Te permite crear sitios WordPress completos o Landing Pages estáticas de inmediato con soporte para certificados SSL de Cloudflare, Let's Encrypt o autofirmados.
8. 🎛️ **Instala la CLI `se2code`**: Deja activo el comando global `se2code` para que administres todo desde cualquier terminal.

---

## 🎯 ¿Qué incluye la Suite?

* 🚀 **Nginx 1.27 Mainline**: Con FastCGI Cache de alto rendimiento, compresión Gzip, HTTP/2 y optimización especial para **Elementor, WooCommerce y WP-Admin** (bypass automático de caché, buffers de 128k/256k y subida de archivos de hasta 256 MB para evitar errores 503 y 413).
* ⚡ **Landing Pages Básicas Ultrarrápidas**: Aprovisionamiento instantáneo de páginas de aterrizaje en HTML/CSS/JS con **0 MB de base de datos** (cero latencia MySQL y 100% libre de riesgos SQLi), tiempos de carga inferiores a 0.2s, certificados SSL automáticos y plantilla moderna de alta conversión.
* ⚡ **Dual PHP-FPM Pools aislados (PHP 8.4 y PHP 8.5)**: Basados en Alpine Linux ultraligeros con OPcache JIT, extensiones compiladas (Redis, GD, Imagick, MariaDB client) y sockets dedicados por sitio.
* 🐬 **MariaDB 11.4 LTS**: Afinada para baja latencia con almacenamiento persistente y buffer pool optimizado.
* 🧠 **Redis 7 In-Memory Cache**: Para Object Caching ultra-rápido en WordPress.
* 🛡️ **WireGuard VPN Server**: Integrado a nivel de host con reglas UFW NAT dinámicas y puertos aleatorios seguros.
* 💾 **Respaldos Granulares**: Motor de backup por sitio (Full, Solo Base de Datos `.sql.gz`, o Solo Archivos `.tar.gz`), con detección inteligente que respeta landing pages sin base de datos.
* 🎛️ **CLI Global `se2code`**: Menú interactivo TUI y subcomandos directos para gestionar sitios WordPress, landing pages, proxies de aplicaciones, certificados SSL y monitoreo del servidor.

---

## 🚀 Landing Pages Básicas (Sin Base de Datos)

El stack incluye un módulo dedicado para desplegar páginas de aterrizaje y sitios estáticos ligeros sin el sobrecosto ni la complejidad de bases de datos MariaDB:

### 🌟 ¿Por qué Landing Pages sin Base de Datos?
* **Consumo Cero en Base de Datos**: 0 MB de uso en RAM y disco para MariaDB.
* **Velocidad Extrema (PageSpeed 100/100)**: Servidas directamente por NGINX desde memoria caché NVMe/RAM con HTTP/2, logrando tiempos de respuesta de **menos de 0.2 segundos**.
* **Seguridad Absoluta**: Superficie de ataque mínima sin riesgo de inyecciones SQL ni vulnerabilidades por plugins desactualizados.
* **Ideal para Campañas Publicitarias**: Google Ads, Meta Ads, captación de prospectos (leads), lanzamientos, portafolios y sitios informativos.

### ⚙️ Dos Modos de Aprovisionamiento:
1. **100% Estático Puro (HTML / CSS / JS)**:
   - Deshabilita la ejecución de PHP en NGINX (`deny all` para `.php`).
   - Cero procesos PHP en memoria. Máxima seguridad e inmutabilidad.
2. **Dinámico Ligero (HTML + PHP 8.4)**:
   - Asigna un pool PHP-FPM dedicado y seguro para procesar formularios (`contact.php`), enviar correos o despachar webhooks a Make, Zapier, n8n o tu CRM.
   - Captura y almacena prospectos automáticamente en un archivo local seguro `leads.json`, el cual está **blindado por NGINX** contra accesos y descargas directas desde la web (`403 Forbidden`).

### 📦 Plantilla de Alta Conversión Incluida:
Cada landing page aprovisionada incluye una plantilla profesional lista para personalizar:
* `index.html`: Hero banner con efecto glow, métricas de confianza, tarjetas de beneficios, formulario de captación de leads, acordeón interactivo de preguntas frecuentes (FAQ) y pie de página.
* `assets/css/style.css`: Diseño en modo oscuro contemporáneo, efectos glassmorphism, micro-animaciones fluidas y variables CSS globales (`:root`) para adaptar paletas de color en segundos.
* `assets/js/main.js`: Lógica nativa (sin dependencias pesadas ni librerías externas) para *smooth scrolling*, control de acordeones FAQ y envío asíncrono (AJAX) del formulario de contacto con feedback visual instantáneo.
* `contact.php`: Procesador ligero con sanitización estricta, trampa anti-bots (*honeypot* invisible) y persistencia segura de datos.
* `README.md`: Documentación interna dentro de la carpeta del sitio con instrucciones claras para editar archivos o reemplazar la plantilla con compilaciones estáticas de **Astro, Vite, Next.js (Static Export), React o Tailwind CSS**.

---

## 🏗️ Arquitectura del Repositorio

```text
se2code-stack/
├── install.sh                   # Instalador Web One-Liner (curl | bash)
├── deploy.sh                    # Script maestro de aprovisionamiento
├── bin/
│   └── se2code                  # CLI interactivo global de gestión (TUI y subcomandos)
├── core/
│   ├── banner.sh                # Branding, paleta ANSI y funciones de formato
│   ├── hardware.sh              # Perfilador de CPU/RAM y cálculo de capacidad
│   ├── swap.sh                  # Creador y optimizador de Swap (Escudo de memoria)
│   ├── ports.sh                 # Validador de puertos dinámicos y reglas UFW
│   └── system.sh                # Detección de SO e instalador de Docker/Compose
├── modules/
│   ├── wordpress/
│   │   ├── docker-compose.yml   # Orquestación Nginx, PHP 8.4/8.5, MariaDB, Redis, PMA
│   │   ├── nginx/               # Snippets de caché, Elementor, SSL, seguridad y estáticos
│   │   ├── php/                 # Dockerfiles y pools dedicados para PHP 8.4 y PHP 8.5
│   │   ├── scripts/
│   │   │   ├── add-site.sh      # Aprovisionador de sitios WordPress (Estándar/Multilenguaje)
│   │   │   ├── add-landing.sh   # 🚀 Aprovisionador de Landing Pages (HTML/CSS/JS sin DB)
│   │   │   ├── list-sites.sh    # Tablas detalladas: WordPress, Landing Pages y Proxies
│   │   │   ├── switch-php.sh    # Selector en caliente PHP 8.4 ↔ PHP 8.5
│   │   │   ├── manage-ssl.sh    # Gestor de certificados (Cloudflare, Let's Encrypt, Self-signed)
│   │   │   ├── backup-site.sh   # Motor de respaldos granulares (compatible con landing pages)
│   │   │   ├── remove-site.sh   # Desmantelador seguro con papelera .trash y backup preventivo
│   │   │   ├── optimize-site.sh # Afinamiento de Nginx Helper, Redis y anti-conflictos
│   │   │   ├── replace-urls.sh  # Reemplazo canónico de URLs (4 variantes ➔ 1 sola)
│   │   │   └── manage-pma.sh    # Gestor bajo demanda de phpMyAdmin
│   │   └── templates/
│   │       ├── nginx-vhost.conf.tpl   # Plantilla vhost WordPress con FastCGI Cache
│   │       ├── landing-vhost.conf.tpl # 🚀 Plantilla vhost Landing Page con Clean URLs
│   │       ├── php-pool.conf.tpl      # Plantilla de pool PHP-FPM dinámico
│   │       ├── se2code-core.php.tpl   # Must-Use Plugin anti-conflictos
│   │       └── landing-page/          # 🚀 Plantilla web responsiva de alta conversión
│   │           ├── index.html
│   │           ├── contact.php
│   │           ├── README.md
│   │           └── assets/ (css/style.css, js/main.js)
│   └── wireguard/
│       ├── docker-compose.yml   # WireGuard en red host
│       └── setup-vpn.sh         # Setup interactivo con puerto dinámico y UFW
├── .env.example                 # Variables de entorno de referencia
├── .gitignore                   # Exclusión anti-ansiedad de datos de clientes
└── README.md                    # Documentación completa del proyecto
```

---

## 🎛️ Menú de Gestión Diario: Comando `se2code`

Una vez instalado, tienes disponible en cualquier terminal el comando global:
```bash
se2code
```

### Opciones disponibles en el menú `se2code`:
* `[1] Listar todos los sitios y landing pages instalados`: Presenta 3 tablas separadas para **Sitios WordPress**, **Landing Pages Básicas** (indicando si son HTML Puro o HTML + PHP) y **Aplicaciones / Proxies** (Astro, Directus, Node, etc.).
* `[2] Crear nuevo sitio WordPress`: Instalación limpia desde cero con descarga oficial del core de WordPress, base de datos MariaDB aislada, Redis Object Cache y SSL.
* `[3] Crear Landing Page Básica (HTML/CSS/JS - Sin Base de Datos)`: Aprovisiona en segundos una página ultrarrápida sin base de datos, con opción de procesamiento dinámico en PHP 8.4 para formularios o 100% estática.
* `[4] Migrar / Importar Sitio Existente`: Importación automatizada de paquetes `.tar.gz` + base de datos `.sql`/`.sql.gz`, auto-detección de `$table_prefix` y reemplazo canónico de dominio (`search-replace`).
* `[5] Agregar sub-sitio / idioma`: Configuración de directorios hijos (ej: `/es`, `/en`) con aislamiento total y bases de datos independientes.
* `[6] Eliminar un sitio o landing page`: Con confirmación estricta de seguridad, respaldo preventivo automático y archivado en papelera de seguridad `.trash/`.
* `[7] Cambiar versión de PHP de un sitio`: Alterna cualquier sitio entre PHP 8.4 y PHP 8.5 en 1 segundo sin caída de servicio.
* `[8] Gestión de Certificados SSL`: Emisión y renovación con Cloudflare Origin CA, Let's Encrypt automático (`acme.sh`) o autofirmados para pruebas.
* `[9] Respaldos Granulares`: Respaldos completos, solo base de datos (`.sql.gz`) o solo archivos (`.tar.gz`), reconociendo landing pages para omitir volcados SQL innecesarios.
* `[10] Purgar Cachés del Servidor`: Vacía la caché FastCGI de NGINX y la memoria de Redis al instante.
* `[11] Optimizar Sitio Existente`: Auto-configuración de Redis Object Cache + Nginx Helper y desactivador de plugins de caché redundantes o conflictivos.
* `[12] Reemplazo Canónico de URLs`: Normaliza las 4 variantes de dominio (`http/https`, `con www/sin www`) a una única URL canónica y actualiza enlaces serializados de Elementor.
* `[13] phpMyAdmin`: Gestor web de bases de datos bajo demanda (iniciar, detener, ver URL segura y restablecer contraseñas).
* `[14-16] Gestión de WireGuard VPN`: Mostrar código QR móvil (Peer 1), ver conexiones activas en vivo o detener el túnel VPN.
* `[17] Securización y Hardening del Servidor`: Creación de usuario sudo dedicado, cambio de puerto SSH, configuración de UFW, Fail2ban y parámetros de Kernel sysctl.
* `[18] Diagnóstico de Hardware y Memoria`: Muestra consumo en tiempo real de RAM, vCPU, Swap y capacidad estimada de sitios.
* `[19] Activar / Ajustar Escudo de Memoria Swap`: Creación y afinamiento de memoria Swap de respaldo (`swappiness=10`).
* `[20] Salir`.

---

## ⚡ Subcomandos Directos por Línea de Comandos (CLI)

Para automatizaciones o administración ágil sin ingresar al menú interactivo, puedes invocar directamente:

```bash
# Listar todos los sitios, landing pages y proxies
se2code list

# Aprovisionar una Landing Page en 1 línea:
# Sintaxis: se2code landing <slug> <dominio> [php: yes/no] [ssl: 1=CF, 2=Let's Encrypt, 3=Self-Signed]
se2code landing milanding milanding.com yes 3

# Purgar todas las cachés FastCGI y Redis
se2code purge-cache

# Generar un respaldo inmediato
se2code backup misitio full

# Iniciar o detener phpMyAdmin
se2code pma

# Administrar certificados SSL
se2code ssl midominio.com

# Reemplazar URLs canónicas
se2code replace-urls

# Cambiar versión de PHP
se2code switch-php
```

---

## 🛡️ Filosofía Git Anti-Ansiedad (Buenas Prácticas DevOps)

Muchos desarrolladores sienten frustración cuando Git les advierte constantemente de "archivos modificados" en el servidor. 

### ¿Por qué pasa esto y cómo lo resolvimos?
El error común es que el repositorio Git intente rastrear las carpetas donde WordPress sube fotos (`uploads`), donde se almacenan las landing pages de clientes, donde MariaDB guarda tablas binarias, o donde NGINX genera cachés.

En **se2Code Stack Server**, el archivo `.gitignore` está blindado para ignorar:
* ❌ Datos de WordPress y Landing Pages (`wp-data/`)
* ❌ Datos binarios de MySQL (`mariadb/data/`)
* ❌ Contraseñas y claves privadas (`.env`, `certs/`, `*.key`)
* ❌ Backups comprimidos (`backups/`) y papelera (`.trash/`)
* ❌ Registros y logs (`*.log`)

### El Flujo de Trabajo Profesional (Ramas `main` y `dev`):
1. **Rama `main`**: Contiene la versión de producción estable y probada del stack.
2. **Rama `dev`**: Contiene mejoras en desarrollo (nuevos scripts, nuevos módulos, etc.).

Cuando quieras actualizar tus servidores con una nueva mejora que hayas programado:
```bash
cd /opt/se2code-stack
git pull origin main
```
Como tus sitios, landing pages y bases de datos están totalmente desacoplados de Git, un `git pull` **nunca romperá tus sitios de clientes** ni causará conflictos de fusión.

---

## 🌐 El Ecosistema se2Code

Este proyecto forma parte del ecosistema integral de infraestructura y desarrollo de **se2Code**, dividido en dos portales complementarios:

| Portal | Enfoque Principal | ¿Qué encontrarás aquí? |
| :--- | :--- | :--- |
| 🛠️ **[se2code.engineer](https://se2code.engineer)** | **Laboratorio Técnico & Navaja Suiza DevOps** | Documentación técnica profunda de estos scripts, tutoriales de administración de servidores, guías de solución de errores (*troubleshooting*), y herramientas interactivas en vivo (generador de contraseñas de alta entropía, calculadoras de recursos, asistentes de configuración VPN WireGuard y más). |
| 💼 **[se2code.com](https://se2code.com)** | **Servicios Comerciales & Consultoría Cloud** | Nuestra agencia de ingeniería de software: desarrollo web de alto rendimiento, arquitectura cloud personalizada, soporte para e-commerce de alto tráfico, migraciones de infraestructura crítica y acuerdos de nivel de servicio (SLA) para empresas. |

---

## 📜 Licencia & Créditos

Desarrollado con dedicación por el equipo de **se2Code**.  
- 🛠️ Artículos técnicos y herramientas: [se2code.engineer](https://se2code.engineer)  
- 💼 Servicios de ingeniería y desarrollo: [se2code.com](https://se2code.com)  

Diseñado para el alto rendimiento, la soberanía de datos y la tranquilidad operativa.
