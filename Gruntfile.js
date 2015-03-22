'use strict';

module.exports = function (grunt) {

    var path = require('path');

    // Load grunt tasks automatically
    require('load-grunt-tasks')(grunt);

    // Time how long tasks take. Can help when optimizing build times
    require('time-grunt')(grunt);

    require('load-grunt-config')(grunt, {
        configPath: path.join(process.cwd(), 'grunt'), //path to task.js files, defaults to grunt dir
        init: true, //auto grunt.initConfig
        config: {
        },
        loadGruntTasks: false
    });

    grunt.registerTask('test', [
        'clean:test',
        'coffee',
        'karma'
    ]);

    grunt.registerTask('build', [
        'clean:dist',
        'coffee',
        'concat',
        'ngAnnotate'
    ]);

    grunt.registerTask('build_lib',['build']);

    grunt.registerTask('default', [
        'test',
        'build'
    ]);

    grunt.registerTask("release", "Release a new version - bumps bower.json, git tags, commits and pushes it", function (target) {
        if (!target)
            target = "patch";
        grunt.task.run(["build_lib", "bump-only:" + target, "bump-commit"]);
    });
};
