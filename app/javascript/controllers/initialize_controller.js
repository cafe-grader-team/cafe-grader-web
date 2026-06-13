// this should be added to <body> and it will connect only once
// its use is to setup any client side initialization
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    // This 'connect' method runs when the controller is attached to an element.
    // For this global override, you'd attach it to <body> or <html>.
    this.setupTurboConfirm();
  }

  // this setup the Turbo confirmation to use Bootstrap Modal
  setupTurboConfirm() {
    Turbo.config.forms.confirm = (dataConfirmMessage, element) => {
    //Turbo.setConfirmMethod((dataConfirmMessage, element) => {
      return new Promise((resolve) => {
        let modalTitle = 'Confirmation'; // Default title
        let modalBody = String(dataConfirmMessage); // Default body (if not an object)
        let parseError = ''; // To hold parsing errors

        try {
          const parsedMessage = JSON.parse(dataConfirmMessage);

          if (typeof parsedMessage === 'object' && parsedMessage !== null) {
            // It's an object, check for title and body
            if (parsedMessage.title && parsedMessage.body) {
              modalTitle = String(parsedMessage.title);
              modalBody = String(parsedMessage.body);
            } else {
              // Object but not in {title: ..., body: ...} format
              modalBody = `The provided object is not in the expected {title: "...", body: "..."} format.<br>
                           Content: <code>${JSON.stringify(parsedMessage, null, 2)}</code>`;
              modalTitle = 'Invalid Confirmation Format'; // Set a more informative title
            }
          }
          // If parsedMessage is not an object (e.g., a number or boolean string),
          // it falls through to use dataConfirmMessage as the body.
        } catch (e) {
          // dataConfirmMessage was not valid JSON, use it as a plain string body
          // No need to set modalBody again, as it's already `String(dataConfirmMessage)`
        }

        // 1. Create a div element for the modal
        const modalDiv = document.createElement('div');
        modalDiv.classList.add('modal', 'fade');
        modalDiv.setAttribute('tabindex', '-1');
        modalDiv.setAttribute('aria-labelledby', 'customConfirmModalLabel');
        modalDiv.setAttribute('aria-hidden', 'true');

        // 2. Populate the modal with Bootstrap's structure
        modalDiv.innerHTML = `
          <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
              <div class="modal-header">
                <h5 class="modal-title" id="customConfirmModalLabel">${modalTitle}</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
              </div>
              <div class="modal-body">
                ${modalBody}
              </div>
              <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-behavior="confirm-cancel">Cancel</button>
                <button type="button" class="btn btn-primary" data-behavior="confirm-accept">Confirm</button>
              </div>
            </div>
          </div>
        `;

        // 3. Append the modal to the body
        document.body.appendChild(modalDiv);

        // 4. Initialize Bootstrap's Modal instance
        const customConfirmModal = new bootstrap.Modal(modalDiv);

        // 5. Get references to our custom buttons
        const confirmButton = modalDiv.querySelector('[data-behavior="confirm-accept"]');
        const cancelButton = modalDiv.querySelector('[data-behavior="confirm-cancel"]');
        const closeButton = modalDiv.querySelector('.btn-close'); // Bootstrap's built-in close

        // 6. Define a function to clean up the modal and resolve the promise
        const cleanupAndResolve = (result) => {
          customConfirmModal.hide(); // Hide the Bootstrap modal
          // Listen for the 'hidden.bs.modal' event to remove the element after animation
          modalDiv.addEventListener('hidden.bs.modal', () => {
            modalDiv.remove(); // Remove the modal HTML from the DOM
            resolve(result); // Resolve the promise
          }, { once: true });

          // Remove the keydown listener if it was added
          document.removeEventListener('keydown', escapeHandler);
        };

        // 7. Add event listeners
        confirmButton.addEventListener('click', () => cleanupAndResolve(true), { once: true });
        cancelButton.addEventListener('click', () => cleanupAndResolve(false), { once: true });
        closeButton.addEventListener('click', () => cleanupAndResolve(false), { once: true }); // Also handle default close button

        // Handle closing via backdrop click or Escape key
        modalDiv.addEventListener('click', (event) => {
          if (event.target === modalDiv) { // Clicked on the backdrop
            cleanupAndResolve(false);
          }
        }, { once: true });

        // Handle Escape key
        const escapeHandler = (event) => {
          if (event.key === 'Escape') {
            cleanupAndResolve(false);
          }
        };
        document.addEventListener('keydown', escapeHandler);

        // 8. Show the modal
        customConfirmModal.show();
      });
    }
  }


}
