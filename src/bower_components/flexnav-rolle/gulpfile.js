var gulp        = require('gulp');
var uglify      = require('gulp-uglify');
var concat      = require('gulp-concat');

gulp.task('js', function() {

      gulp.src('js/jquery.flexnav.js')
      .pipe(concat('js/jquery.flexnav.min.js'))
      .pipe(uglify({preserveComments: false, compress: true, mangle: true}).on('error',function(e){console.log('\x07',e.message);return this.end();}))
      .pipe(gulp.dest('./'));

});