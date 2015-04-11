module.exports = {
    coffee: {
        files: ['src/**/{,*/}*.coffee'],
        tasks: ['newer:coffee','concat','ngAnnotate']
    }
};
