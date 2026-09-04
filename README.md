# ⚡ se2Code Stack Server

> **Suite Profesional de Infraestructura y Despliegue Automatizado**  
> Diseñada para máxima velocidad, alta concurrencia en WordPress y seguridad empresarial.

---

## 🎯 ¿Qué es se2Code Stack Server?

**se2Code Stack Server** es un stack modular de infraestructura como código (IaC) en contenedores Docker y scripts Bash automatizados. Permite desplegar y administrar servidores de producción en segundos con estándares de alta gama:

* 🚀 **Nginx 1.27 Mainline** con FastCGI Cache de alto rendimiento, compresión Gzip, HTTP/2 y optimización especial para **Elementor, WooCommerce y WP-Admin** (bypass automático de caché, buffers ampliados de 128k/256k y protección contra errores 503/413).
* ⚡ **Dual PHP-FPM Pools aislados (PHP 8.4 y PHP 8.5)** basados en Alpine Linux con extensiones compiladas (Redis, GD, Imagick, OPcache JIT, MariaDB client) y sockets dedicados por sitio.
* 🐬 **MariaDB 11.4 LTS** afinada para baja latencia con almacenamiento persistente.
* 🧠 **Redis 7 In-Memory Cache** para Object Caching ultra-rápido en WordPress.
* 🛡️ **WireGuard VPN Server** integrado a nivel de host con reglas UFW NAT dinámicas para gestión privada segura.
* 📊 **Perfilador de Hardware Automático**: Detecta CPU, RAM y Swap, recomendando la cantidad máxima segura de sitios WordPress para evitar caídas por sobrecarga.
* 💾 **Gestor de Swap Automático**: Crea y afina archivos Swap (2 GB / swappiness=10) para proteger la RAM ante picos de tráfico.
* 🎛️ **CLI Global `se2code`**: Menú TUI interactivo para gestionar sitios, cambiar versiones PHP en 1 segundo, generar backups granulares y monitorear el servidor.

---

## 🏗️ Arquitectura del Repositorio

```text
se2code-stack/
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
├── deploy.sh                    # Script maestro de aprovisionamiento
└── README.md                    # Documentación
```

---

## 🚀 Despliegue Rápido (En un nuevo Servidor Ubuntu/Debian)

### 1. Conéctate a tu servidor como `root`:
```bash
ssh root@tu-servidor-ip
```

### 2. Clona el repositorio y ejecuta el instalador:
```bash
git clone https://github.com/TU-USUARIO/se2code-stack.git /opt/se2code-stack
cd /opt/se2code-stack
bash deploy.sh
```

El script interactivo te guiará paso a paso:
1. Analizará el hardware (vCPU, RAM, Swap, Disco).
2. Te sugerirá cuántos sitios WordPress soporta tu servidor de forma óptima.
3. Te ofrecerá crear un archivo Swap si detecta poca memoria disponible.
4. Instalará Docker, Docker Compose y configurará el firewall UFW.
5. Te permitirá elegir qué instalar: **Solo WordPress**, **Solo WireGuard** o la **Suite Completa**.
6. Te preguntará si deseas desplegar sitios WordPress de inmediato (o crearlos después).

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

## 🛡️ Guía Git Anti-Ansiedad (Buenas Prácticas DevOps)

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
