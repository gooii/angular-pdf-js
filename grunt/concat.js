module.exports = {
  options: {
    separator: ';'
  },
  dist: {
    src: ['tmp.js','PDF.js/*.js','.tmp/**/*.js'],
    dest: '.tmp/concat/angular-pdf.js'
  }
};
