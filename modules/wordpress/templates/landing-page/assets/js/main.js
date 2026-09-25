/**
 * se2Code Stack - Landing Page Scripts
 * Ligeros, modulares y de alto rendimiento (sin dependencias externas).
 */

document.addEventListener('DOMContentLoaded', () => {
  // 1. Smooth Scroll para anclas de navegación
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      const targetId = this.getAttribute('href');
      if (targetId === '#' || !targetId) return;
      const targetEl = document.querySelector(targetId);
      if (targetEl) {
        e.preventDefault();
        targetEl.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
      }
    });
  });

  // 2. Acordeón de Preguntas Frecuentes (FAQ)
  const accordionItems = document.querySelectorAll('.accordion-item');
  accordionItems.forEach(item => {
    const header = item.querySelector('.accordion-header');
    if (!header) return;

    header.addEventListener('click', () => {
      const isOpen = item.classList.contains('active');
      
      // Cerrar otros elementos abiertos
      accordionItems.forEach(otherItem => {
        if (otherItem !== item) {
          otherItem.classList.remove('active');
        }
      });

      // Alternar estado actual
      if (isOpen) {
        item.classList.remove('active');
      } else {
        item.classList.add('active');
      }
    });
  });

  // 3. Envío Asíncrono del Formulario de Contacto
  const form = document.getElementById('leadForm');
  const submitBtn = document.getElementById('submitBtn');
  const feedback = document.getElementById('formFeedback');

  if (form && submitBtn && feedback) {
    const btnText = submitBtn.querySelector('.btn-text');
    const btnLoader = submitBtn.querySelector('.btn-loader');

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      // Estado visual de carga
      submitBtn.disabled = true;
      if (btnText) btnText.style.display = 'none';
      if (btnLoader) btnLoader.style.display = 'inline-block';
      feedback.style.display = 'none';
      feedback.className = 'form-feedback';

      const formData = new FormData(form);

      try {
        const response = await fetch(form.action || 'contact.php', {
          method: 'POST',
          body: formData,
          headers: {
            'Accept': 'application/json'
          }
        });

        const data = await response.json().catch(() => null);

        if (response.ok && data && data.success) {
          feedback.textContent = data.message || '¡Gracias! Tu mensaje ha sido enviado correctamente.';
          feedback.className = 'form-feedback success';
          feedback.style.display = 'block';
          form.reset();
        } else {
          const errMsg = (data && data.message) ? data.message : 'Ocurrió un error al enviar el mensaje. Por favor intenta de nuevo.';
          feedback.textContent = errMsg;
          feedback.className = 'form-feedback error';
          feedback.style.display = 'block';
        }
      } catch (err) {
        feedback.textContent = 'No fue posible conectar con el servidor. Revisa tu conexión a internet o contáctanos por WhatsApp.';
        feedback.className = 'form-feedback error';
        feedback.style.display = 'block';
      } finally {
        submitBtn.disabled = false;
        if (btnText) btnText.style.display = 'inline-block';
        if (btnLoader) btnLoader.style.display = 'none';
      }
    });
  }
});
