/*

REQUIRED STUFF
==============
*/

require('es6-promise').polyfill();

var changed     = require('gulp-changed');
var gulp        = require('gulp');
var imagemin    = require('gulp-imagemin');
var sass        = require('gulp-sass');
var sourcemaps  = require('gulp-sourcemaps');
var browserSync = require('browser-sync').create();
var notify      = require('gulp-notify');
var prefix      = require('gulp-autoprefixer');
var minifycss   = require('gulp-minify-css');
var uglify      = require('gulp-uglify');
var cache       = require('gulp-cache');
var concat      = require('gulp-concat');
var util        = require('gulp-util');
var header      = require('gulp-header');
var pixrem      = require('gulp-pixrem');
var exec        = require('child_process').exec;

/*

ERROR HANDLING
==============
*/

var handleError = function(task) {
  return function(err) {

      notify.onError({
        message: task + ' failed, check the logs..',
        sound: false
      })(err);

    util.log(util.colors.bgRed(task + ' error:'), util.colors.red(err));
  };
};

/*

BROWSERSYNC
===========

Notes:
   - Add only file types you are working on - if watching the whole themeDir,
     task trigger will be out of sync because of the sourcemap-files etc.
   - Adding only part of the files will also make the task faster

*/

gulp.task('browsersync', function() {

  var files = [
    '*.{png,jpg,jpeg,gif}',
    '*.html',
    '*.pl',
    '*.js'
  ];

  browserSync.init(files, {
    proxy: "leffat.dev",
    browser: "Google Chrome",
    notify: true
  });

});

gulp.task('styles', function() {

  gulp.src(
    [
      'themes/webapp2.scss',
      'themes/webapp.scss',
      'themes/black.scss',
      'themes/old.scss',
      'themes/white.scss'
    ])
    .pipe(sass({
        compass: false,
        bundleExec: true,
        sourcemap: false,
        style: 'compressed',
        debugInfo: true,
        lineNumbers: true,
        errLogToConsole: true
      }))

    .on('error', handleError('styles'))
    .pipe(prefix('last 3 version', 'safari 5', 'ie 8', 'ie 9', 'opera 12.1', 'ios 6', 'android 4')) // Adds browser prefixes (eg. -webkit, -moz, etc.)
    .pipe(minifycss({keepBreaks:false,keepSpecialComments:0,}))
    .pipe(pixrem())
    .pipe(gulp.dest('../lib/'))
    .pipe(browserSync.stream());

});


/*

SCRIPTS
=======
*/

var currentDate   = util.date(new Date(), 'dd-mm-yyyy HH:ss');
var pkg       = require('./package.json');
var banner      = '/*! <%= pkg.name %> <%= currentDate %> - <%= pkg.author %> */\n';

gulp.task('js', function() {

      gulp.src(
        [
          'moviecat.js'
        ])
        .pipe(concat('all.js'))
        .pipe(uglify({preserveComments: false, compress: true, mangle: true}).on('error',function(e){console.log('\x07',e.message);return this.end();}))
        .pipe(header(banner, {pkg: pkg, currentDate: currentDate}))
        .pipe(gulp.dest('./'));
});

/*

WATCH
=====

*/

// Run the JS task followed by a reload
gulp.task('js-watch', ['js'], browserSync.reload);
gulp.task('watch', ['browsersync'], function() {

  gulp.watch('*.scss', ['styles']);
  gulp.watch('*.js', ['js-watch']);

});
