/*
    Simple Movie Catalog (javascript)
    Copyright (C) 2008 damien.langg@gmail.com
    License: GPL <http://www.gnu.org/licenses/>
*/

var initialized = false;
var debug_enabled = false;
var debug_obj = new Object();
var current_sort;
var sort_steps = 0;

window.onload = moviecat_init;

function moviecat_init()
{
    if (debug_enabled) enable_debug();
    active_sort("SORT_TITLE");
    genre_set_all(true);
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
    for(i=0; i<tbrows.length; i++) {
        r = tbrows[i];
        rows[i] = new Object();
        rows[i].val = getElementsByClassName(r, classname)[0].innerHTML;
        if (class2) {
            rows[i].val2 = getElementsByClassName(r, class2)[0].innerHTML;
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

function active_sort(id)
{
    if (current_sort) {
        current_sort.style.fontWeight = "normal";
        current_sort.style.backgroundColor = "transparent";
        current_sort.style.border = "thin none black";
        current_sort.style.textDecoration = "underline";
    }
    current_sort = document.getElementById(id);
    current_sort.style.fontWeight = "bold";
    current_sort.style.backgroundColor = "silver";
    current_sort.style.border = "thin solid black";
    current_sort.style.textDecoration = "none";
}

function sort_title()
{
    if (!initialized) return;
    var mtable = document.getElementById("MTABLE");
    debug("");
    active_sort("SORT_TITLE");
    table_sort(mtable, "MTITLE", "text")
}

function sort_rating()
{
    if (!initialized) return;
    var mtable = document.getElementById("MTABLE");
    debug("");
    active_sort("SORT_RATING");
    table_sort(mtable, "MRATING", "number", -1, "MTITLE")
}

function sort_runtime()
{
    if (!initialized) return;
    var mtable = document.getElementById("MTABLE");
    debug("");
    active_sort("SORT_RUNTIME");
    table_sort(mtable, "MRUNTIME", "number", +1, "MTITLE")
}


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
            genre.push(gbox[i].id.substr(2));
        }
    }
    debug(genre.join(" "));
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

function do_filter()
{
    if (!initialized) return;
    var genres = genre_get();
    var mtable = document.getElementById("MTABLE");
    var rows = mtable.tBodies[0].rows;
    var i, mg, count = 0;
    for (i=0; i<rows.length; i++) {
        mg = getElementsByClassName(rows[i], "MGENRE")[0].innerHTML;
        if (genre_match(genres, mg.toUpperCase())) {
            //debug_add(i + mg + "<br>");
            rows[i].style.display = '';
            count++;
        } else {
            rows[i].style.display = "none";
        }
    }
    var status = document.getElementById("STATUS");
    var stat = rows.length + " Movies";
    if (count < rows.length) {
        stat = count + " selected out of " + stat;
    }
    status.innerHTML = stat;
}




