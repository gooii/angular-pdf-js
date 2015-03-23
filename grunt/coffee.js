module.exports = {
  compile: {
    options: {
      sourceMap: false
    },
    files: [{
      expand: true,
      cwd: 'src',
      src: '**/*.coffee',
      dest:'.tmp',
      ext:'.js'
    }]
  }
};
