import { Controller } from "@hotwired/stimulus"
import { rowFieldToggle } from "mixins/row_field_toggle";

export default class extends rowFieldToggle(Controller) {

  static targets = ["usersCommand", "userForm", "userFormUserID", "userFormCommand" ,
                    "problemsCommand", "problemForm", "problemFormProblemID", "problemFormCommand" ,
                    "toggleForm",
                   ]

  connect() {
  }

  setActiveTopic(event) {
    const clickedBadge = event.currentTarget;

    // Iterate over all .topic-badge elements
    const activeClass = ["text-bg-secondary"]
    const backgroundClass = ["text-bg-light","border","border-dark-subtle","text-body-tertiary"]
    this.element.querySelectorAll(".topic-badge").forEach((badge) => {
      if (clickedBadge === badge && clickedBadge.classList.contains(activeClass[0]) == false ) {
        badge.classList.add(...activeClass)
        badge.classList.remove(...backgroundClass)
      } else {
        badge.classList.remove(...activeClass)
        badge.classList.add(...backgroundClass)
      }
    });

    //set filter
    const selectedBadge = document.querySelector('.topic-badge.text-bg-secondary')
    const badge_name = (selectedBadge) ? selectedBadge.textContent : ''
    table.column(5).search(badge_name).draw()
  }


}
