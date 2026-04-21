/**
 * Theme Toggle JavaScript
 * Provides dark/light mode switching with localStorage persistence
 */

(function() {
  'use strict';

  // Theme management
  const ThemeManager = {
    // Check for saved theme preference or use system preference
    init: function() {
      const savedTheme = localStorage.getItem('theme');
      const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      
      if (savedTheme) {
        this.setTheme(savedTheme);
      } else if (systemPrefersDark) {
        this.setTheme('dark');
      } else {
        this.setTheme('dark');
      }
      
      // Listen for system theme changes
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
        if (!localStorage.getItem('theme')) {
          this.setTheme(e.matches ? 'dark' : 'dark');
        }
      });
    },

    // Set theme
    setTheme: function(theme) {
      document.documentElement.setAttribute('data-theme', theme);
      this.updateSidebarLink(theme);
    },

    // Toggle between light and dark
    toggle: function() {
      const currentTheme = document.documentElement.getAttribute('data-theme');
      const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
      
      this.setTheme(newTheme);
      localStorage.setItem('theme', newTheme);
      
      // Prevent default link behavior
      return false;
    },

    // Update sidebar link text (icon is handled by CSS ::before)
    updateSidebarLink: function(theme) {
      const link = document.getElementById('theme-toggle-link');
      if (link) {
        if (theme === 'dark') {
          link.textContent = 'Light Mode';
          link.title = 'Switch to Light Mode';
        } else {
          link.textContent = 'Dark Mode';
          link.title = 'Switch to Dark Mode';
        }
      }
    }
  };

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      ThemeManager.init();
    });
  } else {
    ThemeManager.init();
  }

  // Expose to global scope
  window.ThemeManager = ThemeManager;
})();
