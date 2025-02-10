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

function debounce(wait, func, immediate) {
  var timeout
  return function () {
    var context = this,
      args = arguments
    var later = function () {
      timeout = null
      if (!immediate) {
        func.apply(context, args)
      }
    }
    var callNow = immediate && !timeout
    clearTimeout(timeout)
    timeout = setTimeout(later, wait || 200)
    if (callNow) {
      func.apply(context, args)
    }
  }
}

// Ensure requestAnimationFrame works in old browsers
window.requestAnimationFrame =
  window.requestAnimationFrame ||
  window.webkitRequestAnimationFrame ||
  window.mozRequestAnimationFrame ||
  window.oRequestAnimationFrame ||
  window.msRequestAnimationFrame ||
  function (callback) {
    return setTimeout(callback, 16) // 60 FPS fallback
  }

var lastScrollTop = 0
var nav = document.querySelector('.navigation')

function scroll() {
  var scrollTop =
    document.documentElement.scrollTop || document.body.scrollTop || 0

  if (scrollTop > lastScrollTop) {
    // Scrolling down, hide navbar
    if (nav.classList) {
      nav.classList.add('hidden')
    } else {
      nav.className += ' hidden' // Old browser fallback
    }
  } else {
    // Scrolling up, show navbar
    if (nav.classList) {
      nav.classList.remove('hidden')
    } else {
      nav.className = nav.className.replace(/(?:^|\s)hidden(?!\S)/g, '')
    }
  }

  lastScrollTop = scrollTop
}

// Use requestAnimationFrame for smooth performance
function optimizedScroll() {
  requestAnimationFrame(scroll)
}

// Attach debounced scroll event listener
if (window.addEventListener) {
  window.addEventListener(
    'scroll',
    debounce(100, optimizedScroll, false),
    false
  )
} else if (window.attachEvent) {
  window.attachEvent('onscroll', debounce(100, optimizedScroll, false)) // IE8 fallback
}
