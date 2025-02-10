/* Get references to the document body and the dark mode toggle button */
var bodyEl = document.body
var darkButton = document.getElementById('dark-toggle')

// Retrieve stored theme preference from local storage.
var savedTheme = localStorage.getItem('generateTOCdarkMode')

if (savedTheme === 'dark') {
  bodyEl.classList.add('dark')
} else if (savedTheme === 'light') {
  bodyEl.classList.add('light')
} else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
  // If no preference is stored and the system prefers dark mode, enable dark mode.
  bodyEl.classList.add('dark')
}

// Add a click event listener to the toggle button to switch themes.
darkButton.addEventListener('click', function () {
  toggleDarkMode()
})

function toggleDarkMode() {
  if (bodyEl.classList.contains('dark')) {
    bodyEl.classList.remove('dark')
    bodyEl.classList.add('light')
    localStorage.setItem('generateTOCdarkMode', 'light')
  } else {
    bodyEl.classList.remove('light')
    bodyEl.classList.add('dark')
    localStorage.setItem('generateTOCdarkMode', 'dark')
  }
}

// Start Scroll-Hiding Navigation
let lastScrollTop = 0
const nav = document.querySelector('.navigation')

function scroll() {
  let scrollTop = window.scrollY || document.documentElement.scrollTop
  if (scrollTop > lastScrollTop) {
    nav.classList.add('hidden')
  } else {
    nav.classList.remove('hidden')
  }
  lastScrollTop = scrollTop

  // Always show after 1.5s of no scrolling
  clearTimeout(nav.timeout)
  nav.timeout = setTimeout(() => nav.classList.remove('hidden'), 1500)
}

function debounceRAF(func) {
  let ticking = false
  return function () {
    if (!ticking) {
      requestAnimationFrame(() => {
        func()
        ticking = false
      })
      ticking = true
    }
  }
}

window.addEventListener('scroll', debounceRAF(scroll), false)
