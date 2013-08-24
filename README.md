# DEAL
##### Lisp-based tabletop game playtesting tool 
###### (we don't quite have "prototyping" up and running yet)

## Requirements

Deal directly depends on [optima](https://github.com/m2ym/optima), [cl-ppcre](http://weitz.de/cl-ppcre/), [drakma](http://weitz.de/drakma/), [hunchentoot](http://weitz.de/hunchentoot/), [cl-json](http://common-lisp.net/project/cl-json/), [cl-mop](https://github.com/Inaimathi/cl-mop) and [bordeaux-threads](http://common-lisp.net/project/bordeaux-threads/). Other than cl-mop, all of those can be installed using quicklisp. [cl-mop](http://www.cliki.net/cl-mop) can be installed using asdf-install.

It depends on an external SSE publishing service to provide push capability to its clients. The easiest approach is using [nginx](http://wiki.nginx.org/Main) with its [push-stream module](https://github.com/wandenberg/nginx-push-stream-module).

## Installation

- Pick a directory and run the following:

    git clone http://github.com/wandenberg/nginx-push-stream-module.git
    wget http://nginx.org/download/nginx-1.2.0.tar.gz
    tar xzvf nginx-1.2.0.tar.gz
    cd nginx-1.2.0
    ./configure --add-module=../nginx-push-stream-module
    make
    sudo make install

- Clone [this project](https://github.com/Inaimathi/deal)
- Change the config variables in [`package.lisp`](https://github.com/Inaimathi/deal/blob/master/package.lisp) to your liking
- Change the contents of [`nginx-deal`](https://github.com/Inaimathi/deal/blob/master/nginx-deal) to your liking. In particular, by default it binds port `80` for listening, port `9080` for publishing/subscribing, and proxies to port `8080` for any dynamic requests (it should proxy to wherever `hunchentoot` is listening for requests). It also serves static files from `/home/inaimathi/projects/deal`, which is certainly incorrect unless you're me.
- Run your new copy of `nginx` with `nginx-deal` as the conf file. If you did this on Debian, the newly installed binary will be at `/usr/local/nginx/sbin/nginx`. Either add it to your path, or run it from there.
- Run your copy of `deal` by starting a lisp in the appropriate directory, and evaluating `(ql:quickload :deal-ui)`

That's a *lot* more compliacted than I like to make programs, but there isn't a good option for async serving in Common Lisp at the moment. Hopefully I can fix that in a future release. 

In any case, you should now be able to visit `[your-server]/static/index.html` and play.
