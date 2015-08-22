    jQuery(function(jQuery) {
//      jQuery('#MTABLE').mousewheel(function(event, delta) {
//          this.scrollLeft -= (delta * 120);
//          event.preventDefault();
//      })

    jQuery('.movietr').tooltipsy({

    alignTo: 'element',
    showEvent: 'click',
    hideEvent: 'click',
    offset: [0, 0],
    delay: 500,
    show: function (e, $el) {
        $el.fadeIn(500);
    },
    hide: function (e, $el) {
        $el.fadeOut(500);
    },

    });

        jQuery('.tooltipsy, .tooltipsy *').click(function() {
  jQuery('.tooltipsy').hide();
    });

});

