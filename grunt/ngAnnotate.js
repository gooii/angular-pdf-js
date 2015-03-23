module.exports = {
  options: {
    singleQuotes: true
  },
    dist: {
        files: [
            {
                expand: true,
                cwd: '.tmp/concat/',
                src: '*.js',
                dest: 'dist'
            }
        ]
    }
};

