// For setting the ace editor
import { Controller } from "@hotwired/stimulus"
import ace from 'ace-builds'

// ace themes
import 'ace-theme-merbivore'
import 'ace-theme-merbivore_soft'
import 'ace-theme-dracula'
// ace modes
import 'ace-mode-c_cpp'
import 'ace-mode-pascal'
import 'ace-mode-python'
import 'ace-mode-ruby'
import 'ace-mode-haskell'
import 'ace-mode-php'
import 'ace-mode-java'
import 'ace-mode-rust'
import 'ace-mode-golang'
import 'ace-mode-xml'
import 'ace-mode-sql'

export default class extends Controller {

  static targets = [
                    "editor", "languageSelect", "source", "submitSource",
                    "refreshButton", "waitingText"
                   ]

  // this is values that is read from data-editor-delay-value
  static values = {
    delay: { type: Number, default: 5000 }, // Default delay is 5000ms (5 secs)
    asBinary: {type: Boolean, default: false }
  }

  connect() {
    // initialize the editor if we have one
    if (this.hasEditorTarget) this.initEditor();

    // trigger the setLanguage if there is a language selection
    if (this.hasLanguageSelectTarget) this.setLanguage();

    // set up file reader
    this.reader = new FileReader();
    // must use the arrow function else "this" in the function won't 
    // refer to the stimulus Controller
    this.reader.onload = this.#readFile;

  }

  // attached to the select of a language
  // set the syntax highlight rule, using #setEditorHighlight
  setLanguage() {
    //get the selected text
    const select = this.languageSelectTarget
    const selectedOption = select.options[select.selectedIndex]
    const lang = selectedOption.text
    this.#setEditorHighlight(lang)
  }


  // initialize the ace editor
  // load the text, goto line 1 and setup highlight
  initEditor() {
    // load the ace editor
    this.editor = ace.edit(this.editorTarget.id)

    // set theme * tabsize
    this.editor.setTheme('ace/theme/merbivore_soft');
    this.editor.getSession().setTabSize(2);
    this.editor.getSession().setUseSoftTabs(true);

    // load the source code from the element
    this.editor.setValue(this.sourceTarget.value)
    this.editor.gotoLine(1)

    // init the syntax highlight
    this.#setEditorHighlight(this.editorTarget.dataset.language)

    // set readonly mode, if indicated
    if (this.editorTarget.dataset.editorMode == 'view') {
      //this.editor.setOptions({ maxLines: Infinity })
      this.editor.setOptions({ maxLines: 49 })
      this.editor.setReadOnly(true)
    } else {
      this.editor.setOptions({ maxLines: 40, minLines: 40 })
    }

  }

  // attached to the file input, load the file
  // this depends on the "#readFile" functions belows
  loadFileToEditor(event) {
    const file = event.target.files[0];
    this.reader.readAsText(file)
  }

  // attached to form submit
  // copy the editor code to the hidden input for submit
  submit(event) {
    this.submitSourceTarget.value = this.editor.getValue()
  }


  disconnect() {
  }

  // --- private function ---
  #readFile = (theFile) => {
      this.editor.setValue(theFile.target.result);
      this.editor.gotoLine(1);
  };

  // set the syntax highlight
  #setEditorHighlight(language) {
    // skip if there is no editor
    if (!this.hasEditorTarget) return ;

    const languageModes = {
      'Pascal': 'ace/mode/pascal',
      'C++': 'ace/mode/c_cpp',
      'C': 'ace/mode/c_cpp',
      'Ruby': 'ace/mode/ruby',
      'Python': 'ace/mode/python',
      'Java': 'ace/mode/java',
      'Rust': 'ace/mode/rust',
      'Go': 'ace/mode/golang',
      'PHP': 'ace/mode/php',
      'Haskell': 'ace/mode/haskell',
      'PostgreSQL': 'ace/mode/sql',
      'Digital': 'ace/mode/xml',
    };

    // Get the mode from the map, falling back to defaultMode if not found
    const defaultMode = 'ace/mode/c_cpp';
    const mode = languageModes[language] || defaultMode;

    // set the highlight
    this.editor.getSession().setMode(mode);
  }

}

