/*
  (Started from 1.3.3)
  FlexNav.js 1.3.6

  Created by Jason Weaver http://jasonweaver.name
  Released under http://unlicense.org/
  Forked by Roni Laukkarinen https://github.com/ronilaukkarinen/

//
*/
(function() {
  var $;

  $ = jQuery;

  $.fn.flexNav = function(options) {
    var $nav, $top_nav_items, breakpoint, count, nav_percent, nav_width, resetMenu, resizer, settings, showMenu, toggle_selector, touch_selector;
    settings = $.extend({
      'animationOpenSpeed': 500,
      'animationCloseSpeed': 500,
      'animationOpenEffect': 'swing',
      'animationCloseEffect': 'swing',
      'transitionOpacity': true,
      'buttonSelector': '.menu-button',
      'hoverIntent': false,
      'hoverIntentTimeout': 150,
      'calcItemWidths': false,
      'hover': true
    }, options);
    $nav = $(this);
    $nav.addClass('with-js');
    if (settings.transitionOpacity === true) {
      $nav.addClass('opacity');
    }
    $nav.find("li").each(function() {
      if ($(this).has("ul").length) {
        return $(this).addClass("item-with-ul").find("ul").hide();
      }
    });
    if (settings.calcItemWidths === true) {
      $top_nav_items = $nav.find('>li');
      count = $top_nav_items.length;
      nav_width = 100 / count;
      nav_percent = nav_width + "%";
    }
    if ($nav.data('breakpoint')) {
      breakpoint = $nav.data('breakpoint');
    }
    showMenu = function() {
      if ($nav.hasClass('lg-screen') === true && settings.hover === true) {
        if (settings.transitionOpacity === true) {
          return $(this).find('>ul').addClass('menu-show').stop(true, true).animate({
            height: ["toggle", settings.animationOpenEffect],
            opacity: "toggle"
          }, settings.animationOpenSpeed);
        } else {
          return $(this).find('>ul').addClass('menu-show').stop(true, true).animate({
            height: ["toggle", settings.animationOpenEffect]
          }, settings.animationOpenSpeed);
        }
      }
    };
    resetMenu = function() {
      if ($nav.hasClass('lg-screen') === true && $(this).find('>ul').hasClass('menu-show') === true && settings.hover === true) {
        if (settings.transitionOpacity === true) {
          return $(this).find('>ul').removeClass('menu-show').stop(true, true).animate({
            height: ["toggle", settings.animationCloseEffect],
            opacity: "toggle"
          }, settings.animationCloseSpeed);
        } else {
          return $(this).find('>ul').removeClass('menu-show').stop(true, true).animate({
            height: ["toggle", settings.animationCloseEffect]
          }, settings.animationCloseSpeed);
        }
      }
    };
    resizer = function() {
      var selector;
      if ($(window).width() <= breakpoint) {
        $nav.removeClass("lg-screen").addClass("sm-screen");
        if (settings.calcItemWidths === true) {
          $top_nav_items.css('width', '100%');
        }
        selector = settings['buttonSelector'] + ', ' + settings['buttonSelector'] + ' .touch-button';
        $(selector).removeClass('active');
        return $('.one-page li a').on('click', function() {
          return $nav.removeClass('menu-show');
        });
      } else if ($(window).width() > breakpoint) {
        $nav.removeClass("sm-screen").addClass("lg-screen");
        if (settings.calcItemWidths === true) {
          $top_nav_items.css('width', nav_percent);
        }
        $nav.removeClass('menu-show');
        $('.item-with-ul').find('ul.menu-show').each(function(){
            resetMenu.call($(this).parent().get(0));
        });
        if (settings.hoverIntent === true) {
          return $('.item-with-ul').hoverIntent({
            over: showMenu,
            out: resetMenu,
            timeout: settings.hoverIntentTimeout
          });
        } else if (settings.hoverIntent === false) {
          return $('.item-with-ul').off().on('mouseenter', showMenu).on('mouseleave', resetMenu);
        }
      }
    };
    $(settings['buttonSelector']).data('navEl', $nav);
    touch_selector = '.item-with-ul, ' + settings['buttonSelector'];
    $(touch_selector).append('<span class="touch-button"><i class="navicon fa fa-angle-down"></i></span>');
    toggle_selector = settings['buttonSelector'] + ', ' + settings['buttonSelector'] + ' .touch-button';
    $(toggle_selector).on('click', function(e) {
      var $btnParent, $thisNav, bs;
      $(toggle_selector).toggleClass('active');
      e.preventDefault();
      e.stopPropagation();
      bs = settings['buttonSelector'];
      $btnParent = $(this).is(bs) ? $(this) : $(this).parent(bs);
      $thisNav = $btnParent.data('navEl');
      return $thisNav.toggleClass('menu-show');
    });
    $('.touch-button').on('click touchend', function(e) {
      var $sub, $touchButton;
      $sub = $(this).parent('.item-with-ul').find('>ul');
      $touchButton = $(this).parent('.item-with-ul').find('>span.touch-button');
      if ($nav.hasClass('lg-screen') === true) {
        $(this).parent('.item-with-ul').siblings().find('ul.menu-show').removeClass('menu-show').hide();
      }
      if ($sub.hasClass('menu-show') === true) {
        $sub.removeClass('menu-show').stop(true, true).animate({
            height: ["toggle", settings.animationCloseEffect],
            opacity: "toggle"
          }, settings.animationCloseSpeed);
        return $touchButton.removeClass('active');
      } else if ($sub.hasClass('menu-show') === false) {
        $sub.addClass('menu-show').stop(true, true).animate({
            height: ["toggle", settings.animationOpenEffect],
            opacity: "toggle"
          }, settings.animationOpenSpeed);
        return $touchButton.addClass('active');
      }
    });
    $nav.find('.item-with-ul *').focus(function() {
      $(this).parent('.item-with-ul').parent().find(".open").not(this).removeClass("open").hide();
      return $(this).parent('.item-with-ul').find('>ul').addClass("open").show();
    });
    resizer();
    return $(window).on('resize', resizer);
  };

}).call(this);