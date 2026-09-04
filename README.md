# ⚡ se2Code Stack Server

> **Suite Profesional de Infraestructura y Despliegue Automatizado**  
> Diseñada para máxima velocidad, alta concurrencia en WordPress y seguridad empresarial.

---

## 🚀 Instalación en 1 Solo Comando (Estilo CyberPanel / Coolify)

Para desplegar todo el stack en un servidor virgen (Ubuntu 22.04 / 24.04 o Debian 12), entra por SSH como `root` y pega este comando único:

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
7. 🌐 **Aprovisiona sitios**: Te permite crear 0, 1 o múltiples sitios WordPress de inmediato (o crearlos después) con soporte para certificados SSL de Cloudflare.
8. 🎛️ **Instala la CLI `se2code`**: Deja activo el comando global `se2code` para que administres todo desde cualquier terminal.

---

## 🎯 ¿Qué incluye la Suite?

* 🚀 **Nginx 1.27 Mainline**: Con FastCGI Cache de alto rendimiento, compresión Gzip, HTTP/2 y optimización especial para **Elementor, WooCommerce y WP-Admin** (bypass automático de caché, buffers de 128k/256k y subida de archivos de hasta 256 MB para evitar errores 503 y 413).
* ⚡ **Dual PHP-FPM Pools aislados (PHP 8.4 y PHP 8.5)**: Basados en Alpine Linux ultraligeros con OPcache JIT, extensiones compiladas (Redis, GD, Imagick, MariaDB client) y sockets dedicados por sitio.
* 🐬 **MariaDB 11.4 LTS**: Afinada para baja latencia con almacenamiento persistente.
* 🧠 **Redis 7 In-Memory Cache**: Para Object Caching ultra-rápido en WordPress.
* 🛡️ **WireGuard VPN Server**: Integrado a nivel de host con reglas UFW NAT dinámicas y puertos aleatorios seguros.
* 💾 **Respaldos Granulares**: Motor de backup por sitio (Full, Solo Base de Datos `.sql.gz`, o Solo Archivos `.tar.gz`).
* 🎛️ **CLI Global `se2code`**: Menú TUI interactivo para gestionar sitios, cambiar versiones PHP en 1 segundo y monitorear el servidor.

---

## 🏗️ Arquitectura del Repositorio

```text
se2code-stack/
├── install.sh                   # Instalador Web One-Liner (curl | bash)
├── deploy.sh                    # Script maestro de aprovisionamiento
├── bin/
│   └── se2code                  # CLI interactivo global de gestión
├── core/
│   ├── banner.sh                # Branding y funciones de formato
│   ├── hardware.sh              # Perfilador de CPU/RAM y cálculo de capacidad
│   ├── swap.sh                  # Creador y optimizador de Swap
│   ├── ports.sh                 # Validador de puertos dinámicos y UFW
│   └── system.sh                # Detección de SO e instalador de Docker/Compose
├── modules/
│   ├── wordpress/
│   │   ├── docker-compose.yml   # Orquestación Nginx, PHP 8.4/8.5, MariaDB, Redis
│   │   ├── nginx/               # Snippets de caché, Elementor, SSL y cabeceras
│   │   ├── php/                 # Dockerfiles y pools para PHP 8.4 y PHP 8.5
│   │   ├── scripts/             # add-site, switch-php, backup-site, remove-site
│   │   └── templates/           # Plantillas Nginx y PHP-FPM con buffers altos
│   └── wireguard/
│       ├── docker-compose.yml   # WireGuard en red host
│       └── setup-vpn.sh         # Setup interactivo con puerto dinámico y UFW
├── .env.example                 # Variables de entorno de referencia
├── .gitignore                   # Exclusión anti-ansiedad de datos de clientes
└── README.md                    # Documentación
```

---

## 🎛️ Menú de Gestión Diario: Comando `se2code`

Una vez instalado, tienes disponible en cualquier terminal el comando global:
```bash
se2code
```

### Opciones disponibles en el menú:
* `[1] Crear nuevo sitio WordPress`: Pide dominio, usuario, genera BD y pega certificados SSL de Cloudflare.
* `[2] Cambiar versión de PHP`: Alterna cualquier sitio entre PHP 8.4 y PHP 8.5 en 1 segundo sin caída de servicio.
* `[3] Purgar FastCGI Cache`: Limpia la caché Nginx de un sitio específico o de todos.
* `[4] Generar Backup Granular`:
  * **Completo** (Base de datos + Archivos `wp-content`).
  * **Solo Base de Datos** (`.sql.gz`).
  * **Solo Archivos** (`.tar.gz` excluyendo cachés temporales).
* `[5] Renovar / Cambiar Certificado SSL`: Pega un nuevo certificado de Cloudflare Origin CA sin reiniciar Nginx.
* `[6] Eliminar un sitio WordPress`: Con confirmación de seguridad y respaldo preventivo automático.
* `[7] Ver QR y Configuración WireGuard`: Muestra el código QR para escanear en la app móvil de WireGuard.
* `[8] Reiniciar Servicios`: Reinicia el stack Nginx, PHP, MariaDB o Redis con un solo toque.
* `[9] Diagnóstico de Hardware y Capacidad`: Muestra consumo en tiempo real de RAM, vCPU y sitios soportados.
* `[10] Optimizar Memoria Swap`: Aumenta o recrea el archivo Swap del sistema.

---

## 🛡️ Filosofía Git Anti-Ansiedad (Buenas Prácticas DevOps)

Muchos desarrolladores sienten frustración cuando Git les advierte constantemente de "archivos modificados" en el servidor. 

### ¿Por qué pasa esto y cómo lo resolvimos?
El error común es que el repositorio Git intente rastrear las carpetas donde WordPress sube fotos (`uploads`), donde MariaDB guarda tablas binarias, o donde Nginx genera cachés.

En **se2Code Stack Server**, el archivo `.gitignore` está blindado para ignorar:
* ❌ Datos de WordPress (`wp-data/`)
* ❌ Datos binarios de MySQL (`mariadb/data/`)
* ❌ Contraseñas y claves privadas (`.env`, `certs/`, `*.key`)
* ❌ Backups comprimidos (`backups/`)
* ❌ Registros y logs (`*.log`)

### El Flujo de Trabajo Profesional (Ramas `main` y `dev`):
1. **Rama `main`**: Contiene la versión de producción estable y probada del stack.
2. **Rama `dev`**: Contiene mejoras en desarrollo (nuevos scripts, nuevos módulos como Nextcloud, etc.).

Cuando quieras actualizar tus servidores con una nueva mejora que hayas programado:
```bash
cd /opt/se2code-stack
git pull origin main
```
Como tus sitios y bases de datos están totalmente desacoplados de Git, un `git pull` **nunca romperá tus sitios de clientes** ni causará conflictos de fusión.

---

## 📜 Licencia & Créditos

Desarrollado con dedicación por **se2Code**. Diseñado para el alto rendimiento y la tranquilidad operativa.
