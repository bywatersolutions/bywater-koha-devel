module.exports = {
    entry: {
        moredetail: './koha-tmpl/intranet-tmpl/prog/js/public/moredetail.js',
    },
    output: {
        path: './koha-tmpl/intranet-tmpl/prog/js/app',
        filename: '[name].js' // Template based on keys in entry above
    },
    module: {
        loaders: [
            {
                test: /\.js$/,
                loader: 'babel-loader',
                query: {
                    presets: ['react']
                }
            }
        ]
    },
    resolve: {
        // you can now require('file') instead of require('file.js')
        extensions: ['', '.js', '.json']
    }
};
