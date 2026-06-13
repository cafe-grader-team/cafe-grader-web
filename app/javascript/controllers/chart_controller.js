import { Controller } from "@hotwired/stimulus"
import "chart" // UMD build: sets window.Chart as side effect

// Chart presets
// Usage:
//   %canvas{ data: { controller: 'chart', chart_data_value: @chart_dataset } }
//   %canvas{ data: { controller: 'chart', chart_data_value: @dataset, chart_preset_value: 'line' } }
const PRESETS = {
  bar: {
    type: 'bar',
    options: {
      plugins: {
        legend: { display: false },
      },
    },
  },
  line: {
    type: 'line',
    options: {
      responsive: true,
      maintainAspectRatio: false,
      elements: {
        point: { pointStyle: false },
      },
    },
  },
  submission_line: {
    type: 'line',
    options: {
      aspectRatio: 9,
      plugins: {
        legend: { display: false },
      },
      scales: {
        y: {
          title: { text: '#sub', display: true },
        },
        x: {
          ticks: { maxRotation: 0 },
        },
      },
    },
  },
}

export default class extends Controller {
  static values = {
    data: Object,
    preset: { type: String, default: 'bar' },
  }

  connect() {
    // Canvas may exist before AJAX data arrives — skip if empty
    if (Object.keys(this.dataValue).length > 0) {
      this._drawChart()
    }
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  dataValueChanged() {
    if (Object.keys(this.dataValue).length === 0) return

    if (this.chart) {
      this.chart.destroy()
    }
    this._drawChart()
  }

  _drawChart() {
    const preset = PRESETS[this.presetValue] || PRESETS.bar
    Chart.defaults.font.size = 15
    this.chart = new Chart(this.element, {
      type: preset.type,
      data: this.dataValue,
      options: preset.options,
    })
  }
}
