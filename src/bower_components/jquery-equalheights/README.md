# jquery-equalHeights

Equalize heights of containers via jQuery, with additional options.

[![Bower version](https://badge.fury.io/bo/jquery-equalheights.svg)](http://badge.fury.io/bo/jquery-equalheights)

## Install with Bower

```
bower install jquery-equalheights
```


## Usage

```js
$(objects).equalHeights([options]);
```


## Options

* minHeight - sets all selections to at least the given height (default 0)
* maxHeight - all selections are no more than the given height (no default)
* overflow  - CSS overflow value to apply to selections (default "auto")
* extra     - additional height to add to each element (default 0)


## Dynamic Content

Because this plug-in sets the height of all the passed objects, if the content of those objects later changes, the heights may need to be recalculated.  In this case, just call the function again.


## Credits

This code is largely based on the work of Rob Glazebrook and his code at <http://www.cssnewbie.com/equalheights-jquery-plugin/>.

I've added the ability to pass some additional options to Rob's code, and cleaned some stuff up as it relates to current versions of jQuery.
