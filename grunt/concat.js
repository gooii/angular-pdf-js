module.exports = {
  options: {
    separator: ';'
  },
  dist: {
    src: ['PDF.js/*.js','.tmp/**/*.js'],
    dest: '.tmp/concat/angular-pdf.js'
  }
};
