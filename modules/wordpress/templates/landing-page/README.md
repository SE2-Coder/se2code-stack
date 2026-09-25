# ⚡ Landing Page — se2Code Stack

Landing page de alto rendimiento, optimizada para conversiones y tiempos de carga instantáneos (PageSpeed 100/100).

---

## 📁 Estructura de Archivos

```text
.
├── index.html              # Estructura principal y contenido
├── contact.php             # Procesador de formulario (captura leads en leads.json)
├── leads.json              # Registro local de leads (protegido contra acceso web por NGINX)
└── assets/
    ├── css/
    │   └── style.css       # Estilos modernos con paleta Tailwind/Dark mode y variables CSS
    └── js/
        └── main.js         # Lógica interactiva: Smooth scroll, FAQ accordion y AJAX submit
```

---

## 🛠️ Personalización

1. **Editar Textos y Oferta:**
   Modifica directamente `index.html`. Puedes cambiar el logo, textos del Hero, beneficios, testimonios y preguntas frecuentes.

2. **Personalizar Colores y Estilos:**
   Abre `assets/css/style.css`. Al inicio encontrarás las variables CSS globales (`:root`):
   ```css
   --primary: #38bdf8;
   --primary-glow: rgba(56, 189, 248, 0.4);
   --bg-body: #090d16;
   ```
   Cambiando estas variables puedes adaptar la landing a la paleta de cualquier marca en segundos.

3. **Gestión de Leads del Formulario:**
   - Cada envío se guarda automáticamente en `leads.json`.
   - NGINX tiene reglas de seguridad activas que bloquean la descarga directa de archivos `.json`, garantizando la privacidad de tus prospectos.
   - En `contact.php` puedes descomentar o conectar llamadas a Webhooks (Make, Zapier, n8n, CRM o bots de Telegram) enviando un cURL POST.

4. **Sustituir por un Proyecto Estático Personalizado:**
   Si deseas utilizar un framework moderno (Astro, Vite, Next.js Static Export, React o HTML/Tailwind propio), simplemente sube los archivos de la carpeta `dist/` u `out/` a este directorio reemplazando estos archivos de plantilla. NGINX ya está preconfigurado con soporte para Clean URLs y Brotli/Gzip.

---

## 🔒 Seguridad y Rendimiento

- **Sin Base de Datos:** Cero superficie de ataque SQLi, cero latencia MySQL y 100% de memoria RAM liberada.
- **SSL/TLS Nativo:** Certificados con HTTP/2 automático.
- **Cabeceras de Seguridad:** HSTS, X-Content-Type-Options, X-Frame-Options y Referrer-Policy integradas.
- **Caché de Activos Estáticos:** 1 año de caché para imágenes, fuentes, CSS y JS con `immutable`.
