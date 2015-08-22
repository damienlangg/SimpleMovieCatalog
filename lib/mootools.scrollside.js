/*
---
description:     ScrollSide

authors:
  - David Walsh (http://davidwalsh.name)

license:
  - MIT-style license

requires:
  core/1.2.1:   '*'

provides:
  - ScrollSide
...
*/
var ScrollSide = new Class({
	
	/* implements */
	Implements: [Options,Events],
	
	/* options */
	options: {
		reset: true,
		movement: 75 /*,
		onScrollUp: $empty,
		onScrollDown: $empty
		*/
	},
	
	/* initialization */
	initialize: function(container,options) {
		/* set options */
		this.setOptions(options);
		this.container = document.id(container);
		if(this.options.reset) { this.container.scrollTo(0,0); }
		this.containerWidth = this.container.getScrollSize().x;
		this.position = this.container.getScroll().x;
		/* add the listener */
		this.addListeners();
	},
	
	/* listen for scrolling */
	addListeners: function() {
		/* scroll reset */
		var scrollContainer = (this.container == document.id(document.body) ? window : this.container);
		scrollContainer.addEvent('scroll',function() {
			this.position = this.container.getScroll().x;
		}.bind(this));
		/* mousewheeling */
		this.container.addEvent('mousewheel',function(e) {
			if(e) { e.stop(); }
			var pos;
			/* scroll down/right */
			if(e.wheel < 0) {
				this.fireEvent('scrollUp',[e]);
				pos = this.position + this.options.movement;
				this.position = (pos <= this.containerWidth ? pos : this.containerWidth);
			}
			/* scroll up/left */
			else{
				this.fireEvent('scrollDown',[e]);
				pos = this.position - this.options.movement;
				this.position = (pos > 0 ? pos : 0);
			}
			this.container.scrollTo(this.position,0);
		}.bind(this));
	}
});
