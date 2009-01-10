/*
    Simple Movie Catalog (javascript)
    Copyright (C) 2008 damien.langg@gmail.com
    License: GPL <http://www.gnu.org/licenses/>
*/

var initialized = false;
var debug_enabled = false;
var debug_obj = new Object();
var current_sort;
var current_dir = 1;
var sort_steps = 0;

window.onload = moviecat_init;

function moviecat_init()
{
    if (debug_enabled) enable_debug();
    active_sort("SORT_TITLE", 1);
    init_filter();
    initialized = true;
}

function enable_debug()
{
    debug_obj = document.getElementById("DEBUG");
    if (!debug_obj) {
        var body = document.getElementsByTagName("body")[0];
        body.innerHTML = "<b id=DEBUG>.</b><br>" + body.innerHTML;
        debug_obj = document.getElementById("DEBUG");
    }
    if (debug_obj) {
        debug_enabled = true;
    } else {
        debug_enabled = false;
        debug_obj = new Object();
        alert("enable_debug() Failed!");
    }
}

function debug(x)
{
    if (!debug_enabled) return;
    debug_obj.innerHTML = x;
}

function debug_add(x)
{
    if (!debug_enabled) return;
    debug_obj.innerHTML += x;
}



function getElementsByClassNameX(className, tag, elm){
	var testClass = new RegExp("(^|\\s)" + className + "(\\s|$)");
	var tag = tag || "*";
	var elm = elm || document;
	var elements = (tag == "*" && elm.all)? elm.all : elm.getElementsByTagName(tag);
	var returnElements = [];
	var current;
	var length = elements.length;
	for(var i=0; i<length; i++){
		current = elements[i];
		if(testClass.test(current.className)){
			returnElements.push(current);
		}
	}
	return returnElements;
}

function getElementsByClassName(node, classname) {
    if (node.getElementsByClassName) {
        return node.getElementsByClassName(classname);
    } else {
        return getElementsByClassNameX(classname, "*", node);
    }
}

function getValue(obj, cname)
{
    var e = getElementsByClassName(obj, cname);
    if (!e || !e[0]) return undefined;
    return e[0].innerHTML;
}

function getNumValue(obj, cname)
{
    var v = Number(getValue(obj, cname));
    if (!v || isNaN(v)) return 0;
    return v;
}


function cmp_number(a,b)
{
    if (isNaN(a)) a = 0;
    if (isNaN(b)) b = 0;
    return a - b;
}

function cmp_text(a,b)
{
    if (a < b) return -1;
    if (a == b) return 0;
    return 1;
}

function by_number(a,b)
{
    sort_steps++;
    var cmp = cmp_number(a.val, b.val);
    if (!cmp && a.val2 && b.val2) {
        // if equal use secondary key
        return cmp_text(a.val2, b.val2);
    }
    return cmp;
}

function by_text(a,b)
{
    sort_steps++;
    return cmp_text(a.val, b.val);
}

function by_number_rev(a,b)
{
    var cmp = - cmp_number(a.val, b.val);
    if (!cmp && a.val2 && b.val2) {
        // if equal use secondary key
        // (intentionaly not reversed)
        return cmp_text(a.val2, b.val2);
    }
    return cmp;
}

function by_text_rev(a,b)
{
    return - by_text(a,b);
}

function table_sort(table, classname, datatype, direction, class2)
{
    var tbody = table.tBodies[0];
    var tbrows = tbody.rows;
    var rows = new Array(tbrows.length);
    var r, i;
    var t0, t1, t2;
    var sort_fun;
    t0 = t1 = new Date().getTime();
    debug_add("table_sort("+classname+") ");
    for(i=0; i<tbrows.length; i++) {
        r = tbrows[i];
        rows[i] = new Object();
        rows[i].val = getValue(r, classname);
        if (class2) {
            rows[i].val2 = getValue(r, class2);
        }
        rows[i].row = r;
    }
    t2 = new Date().getTime();
    debug_add("times: prepare: " + (t2-t1) + " ms ");
    sort_steps = 0;
    t1 = new Date().getTime();
    if (datatype == "number") {
        sort_fun = (direction < 0) ? by_number_rev :  by_number;
    } else { //if (datatype == "text") {
        sort_fun = (direction < 0) ? by_text_rev :  by_text;
    }
    rows.sort(sort_fun);
    t2 = new Date().getTime();
    debug_add("sort: " + (t2-t1) + " ms ");
    t1 = new Date().getTime();
    // rearrange table
    for(i=0; i<tbrows.length; i++) {
        //tbody.appendChild(rows[i].row);
        tbody.insertBefore(rows[i].row, tbrows[i]);
    }
    t2 = new Date().getTime();
    debug_add("rearrange: " + (t2-t1) + " ms ");
    debug_add("total: " + (t2-t0) + " ms ");
    debug_add("steps: " + sort_steps);
}

function active_sort(id, dir)
{
    var new_sort = document.getElementById(id);
    if (current_sort) {
        if (current_sort == new_sort) {
            dir = -current_dir;
        }
        current_sort.style.fontWeight = "normal";
        current_sort.style.backgroundColor = "transparent";
        current_sort.style.border = "thin none black";
        current_sort.style.textDecoration = "underline";
    }
    current_sort = new_sort;
    current_dir = dir;
    current_sort.style.fontWeight = "bold";
    current_sort.style.backgroundColor = "silver";
    current_sort.style.border = "thin solid black";
    current_sort.style.textDecoration = "none";
    var sort_dir = document.getElementById("SORT_DIRECTION");
    if (sort_dir) sort_dir.parentNode.removeChild(sort_dir);
    sort_dir = document.createElement('span');
    sort_dir.id = "SORT_DIRECTION";
    //sort_dir.innerHTML = (dir > 0) ? "&uarr;" : "&darr;";
    sort_dir.innerHTML = (dir > 0) ? "<small>&#9650;</small>" : "<small>&#9660;</small>";

    current_sort.appendChild(sort_dir);
    return dir;
}

function do_sort(name, dtype, dir)
{
    if (!initialized) return;
    debug("");
    var mtable = document.getElementById("MTABLE");
    var sname = "SORT_" + name;
    var cname = "M" + name;
    dir = active_sort(sname, dir);
    table_sort(mtable, cname, dtype, dir, "MTITLE")
}

function sort_title()
{
    do_sort("TITLE", "text", +1)
}

function sort_rating()
{
    do_sort("RATING", "number", -1)
}

function sort_runtime()
{
    do_sort("RUNTIME", "number", +1)
}

function sort_year()
{
    do_sort("YEAR", "number", -1)
}

function sort_dirtime()
{
    do_sort("DIRTIME", "number", -1)
}

function sort_user(x)
{
    do_sort("UV"+x, "number", -1)
}

// genre filter

function genre_set_all(x)
{
    var gtable = document.getElementById("GENRE_TABLE");
    var gbox = gtable.getElementsByTagName("input");
    var i;
    for (i=0; i<gbox.length; i++) {
        if (gbox[i].type == "checkbox") {
            gbox[i].checked = x;
        }
    }
}

function genre_all()
{
    if (!initialized) return;
    genre_set_all(true);
    do_filter();
}

function genre_none()
{
    if (!initialized) return;
    genre_set_all(false);
    do_filter();
}

function genre_one(x)
{
    if (!initialized) return;
    debug(x);
    var gbox = document.getElementById(x);
    if (gbox.type == "checkbox") {
        genre_set_all(false);
        gbox.checked = true;
        do_filter();
    }
}

function genre_get()
{
    var gtable = document.getElementById("GENRE_TABLE");
    var gbox = gtable.getElementsByTagName("input");
    var genre = new Array();
    var i;
    for (i=0; i<gbox.length; i++) {
        if (gbox[i].type == "checkbox" && gbox[i].checked) {
            genre.push(gbox[i].id.substr(2)); // strip G_
        }
    }
    debug_add("<br>Genre: " + genre.join(" "));
    return genre;
}

function genre_match(garray, gstring)
{
    var i;
    for (i=0; i<garray.length; i++) {
        if (gstring.match(garray[i])) return true;
    }
    return false;
}

// Tags

function tag_all()
{
    var table = document.getElementById("TAG_TABLE");
    var input = table.getElementsByTagName("input");
    var i;
    for (i=0; i<input.length; i++) {
        if (input[i].type == "radio" && input[i].value == "all") {
            input[i].checked = 1;
        }
    }
    do_filter();
}

function tag_set(tid, val)
{
    if (!initialized) return;
    debug(tid +"="+ val);
    var tag = document.getElementById(tid+"_"+val);
    if (tag.type == "radio") {
        tag.checked = true;
        do_filter();
    }
}

function get_tags()
{
    var table = document.getElementById("TAG_TABLE");
    var input = table.getElementsByTagName("input");
    var tags = new Array();
    var i;
    debug_add("<br>Tags: ");
    for (i=0; i<input.length; i++) {
        if (input[i].type == "radio" && input[i].checked) {
            var tag = new Object();
            tag.name = input[i].name.substr(4); // strip TAG_
            tag.value = input[i].value;
            tags.push(tag);
            debug_add(tag.name + "=" + tag.value + " ");
        }
    }
    return tags;
}

function indexOf(arr, val)
{
    if (arr.indexOf) {
        // FF
        return arr.indexOf(val);
    }
    // MSIE
    var i;
    for (i=0; i<arr.length; i++) {
        if (arr[i] == val) return i;
    }
    return -1;
}

function tag_match(tagstr, tagarray)
{
    var tags = tagstr ? tagstr.toUpperCase().split(" ") : [];
    var i, present;
    for (i=0; i<tagarray.length; i++) {
        if (tagarray[i].value == "all") continue;
        if (indexOf(tags, tagarray[i].name) >= 0) {
            present = true;
        } else {
            present = false;
        }
        if (tagarray[i].value == "set" && !present) return false;
        if (tagarray[i].value == "not" && present) return false;
    }
    return true;
}

var filter_count = 0;

function do_filter()
{
    if (!initialized) return;
    filter_count++;
    debug("Filter["+filter_count+"]");
    var genres = genre_get();
    var tags = get_tags();
    var mtable = document.getElementById("MTABLE");
    var rows = mtable.tBodies[0].rows;
    var i, mg, count = 0;
    var ymin, ymax, rmin, rmax, tmin, tmax;
    var my, mr, mrt, mtags;
    var show;
    ymin = document.getElementById("YMIN").value;
    ymax = document.getElementById("YMAX").value;
    rmin = document.getElementById("RMIN").value;
    rmax = document.getElementById("RMAX").value;
    tmin = document.getElementById("TMIN").value;
    tmax = document.getElementById("TMAX").value;
    debug_add("<br>Ranges: Y:"+ymin+"-"+ymax+" R:"+rmin+"-"+rmax+" T:"+tmin+"-"+tmax);
    var t1 = new Date().getTime();
    for (i=0; i<rows.length; i++) {
        mg = getValue(rows[i], "MGENRE");
        show = genre_match(genres, mg.toUpperCase());
        my = getNumValue(rows[i], "MYEAR");
        if (my < ymin || my > ymax) show = false;
        mr = getNumValue(rows[i], "MRATING");
        if (mr < rmin || mr > rmax) show = false;
        mrt = getNumValue(rows[i], "MRUNTIME");
        if (mrt < tmin || mrt > tmax) show = false;
        mtags = getValue(rows[i], "MTAGS");
        if (!tag_match(mtags, tags)) show = false;
        if (show) {
            //debug_add(i + mg + "<br>");
            rows[i].style.display = '';
            count++;
        } else {
            rows[i].style.display = "none";
        }
    }
    var t2 = new Date().getTime();
    var fstatus = document.getElementById("STATUS");
    var stat = "";
    if (count < rows.length) {
        stat = count + " / ";
    } // else { stat = "All "; }
    stat += rows.length + " Movies";
    debug_add("  Time:" + (t2-t1) + " ms ");
    //stat += " [" + (t2-t1) + "]";
    fstatus.innerHTML = stat;
}

function numbersOnly(obj)
{
    obj.value = obj.value.replace(/[^0-9]/g, '');
}

function filter_reset()
{
    document.getElementById('FORM_FILTER').reset();
    do_filter()
}

function sh_filter(x, show)
{
    var showf = document.getElementById('SHOW_FILTER' + x);
    var hidef = document.getElementById('HIDE_FILTER' + x);
    if (show) {
        showf.style.display = 'none';
        hidef.style.display = '';
    } else {
        showf.style.display = '';
        hidef.style.display = 'none';
    }
}

function show_filter(x)
{
    sh_filter(x, true);
}

function hide_filter(x)
{
    sh_filter(x, false);
}

function init_filter()
{
    genre_set_all(true);
    tag_all();
    sh_filter(1, true);
    sh_filter(2, true);
    sh_filter(3, false);
}



