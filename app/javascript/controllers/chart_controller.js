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
  stacked_bar: {
    type: 'bar',
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: { x: { stacked: true }, y: { stacked: true, beginAtZero: true } },
      plugins: { legend: { position: 'bottom' } },
    },
  },
  multiline: {
    type: 'line',
    options: {
      responsive: true,
      maintainAspectRatio: false,
      spanGaps: true,
      elements: { point: { radius: 2 } },
      plugins: { legend: { position: 'bottom' } },
      scales: { y: { beginAtZero: true, title: { display: true, text: 'seconds' } } },
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
    // Canvas may exist before AJAX data arrives — skip if empty. Guard on
    // this.chart: when data is present at connect time (server-rendered, e.g.
    // the contest AI-usage charts), Stimulus has already fired
    // dataValueChanged and drawn the chart before connect() runs; drawing
    // again here would throw "Canvas is already in use".
    if (!this.chart && Object.keys(this.dataValue).length > 0) {
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
