import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect(event) {
    this.element.addEventListener('copy', this.strip_zws_from_copy)
  }

  // this is a new handler for copying, it will remove all zero width space
  strip_zws_from_copy(event) {
    // Get the text that the browser would normally copy
    const selectedText = window.getSelection().toString();

    // Define the Zero-Width Space character (U+200B)
    const zeroWidthSpace = '\u200b';

    // Remove all instances of ZWS from the selected text
    const cleanedText = selectedText.replace(new RegExp(zeroWidthSpace, 'g'), '');

    // Prevent the default copy behavior
    event.preventDefault();

    // Set the clipboard data to the cleaned text
    event.clipboardData.setData('text/plain', cleanedText);
  }

  disconnect() {
  }
}
