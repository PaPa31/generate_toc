/* Get references to the document body and the dark mode toggle button */
var bodyEl = document.body
var darkButton = document.getElementById('dark-toggle')

// Retrieve stored theme preference from local storage.
var savedTheme = localStorage.getItem('generateTOCdarkMode')

if (savedTheme === 'dark') {
  bodyEl.classList.add('dark')
  darkButton.innerHTML = '☀️' // Set sun icon for light mode toggle
} else if (savedTheme === 'light') {
  bodyEl.classList.add('light')
  darkButton.innerHTML = '🌙' // Set moon icon for dark mode toggle
} else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
  // If no preference is stored and the system prefers dark mode, enable dark mode.
  bodyEl.classList.add('dark')
  darkButton.innerHTML = '☀️'
} else {
  darkButton.innerHTML = '🌙'
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
    darkButton.innerHTML = '🌙' // Change to moon icon
  } else {
    bodyEl.classList.remove('light')
    bodyEl.classList.add('dark')
    localStorage.setItem('generateTOCdarkMode', 'dark')
    darkButton.innerHTML = '☀️' // Change to sun icon
  }
}

// Start Scroll-Hiding Navigation
;(function () {
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
        nav.className += ' hidden' // Fallback for old browsers
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

    // Always show navbar after 1.5s of no scrolling
    clearTimeout(nav.timeout)
    nav.timeout = setTimeout(function () {
      if (nav.classList) {
        nav.classList.remove('hidden')
      } else {
        nav.className = nav.className.replace(/(?:^|\s)hidden(?!\S)/g, '')
      }
    }, 1500)
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

  // Polyfill requestAnimationFrame for older browsers
  window.requestAnimationFrame =
    window.requestAnimationFrame ||
    window.webkitRequestAnimationFrame ||
    window.mozRequestAnimationFrame ||
    window.oRequestAnimationFrame ||
    window.msRequestAnimationFrame ||
    function (callback) {
      return setTimeout(callback, 16) // 60 FPS fallback
    }

  function debounceRAF(func) {
    var ticking = false
    return function () {
      if (!ticking) {
        requestAnimationFrame(function () {
          func()
          ticking = false
        })
        ticking = true
      }
    }
  }

  // Attach debounced scroll event listener
  if (window.addEventListener) {
    window.addEventListener('scroll', debounceRAF(scroll), false)
  } else if (window.attachEvent) {
    window.attachEvent('onscroll', debounce(100, scroll, false)) // IE8 fallback
  }
})()
