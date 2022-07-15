var app = window.angular.module("routerApp", [
]);

app.config([
    "$controllerProvider",
    "$provide",
    "$compileProvider",
function( $controllerProvider, $provide, $compileProvider ) {

    // Let's keep the older references.
    app._controller = app.controller;
    app._service = app.service;
    app._factory = app.factory;
    app._value = app.value;
    app._directive = app.directive;

    // Provider-based controller.
    app.controller = function( name, constructor ) {

        $controllerProvider.register( name, constructor );
        return( this );

    };

    // Provider-based service.
    app.service = function( name, constructor ) {
        $provide.service( name, constructor );
        return( this );
    };

    // Provider-based factory.
    app.factory = function( name, factory ) {
        $provide.factory( name, factory );
        return( this );
    };

    // Provider-based value.
    app.value = function( name, value ) {
        $provide.value( name, value );
        return( this );

    };

    // Provider-based directive.
    app.directive = function( name, factory ) {
        $compileProvider.directive( name, factory );
        return( this );
    };

    // NOTE: You can do the same thing with the "filter"
    // and the "$filterProvider"; but, I don't really use
    // custom filters.

}]);

app.config([
    "$httpProvider",
function($httpProvider) {
    $httpProvider.defaults.headers.post['Content-Type'] = 'application/x-www-form-urlencoded;charset=utf-8';
    $httpProvider.defaults.withCredentials = true;
}]);

app.service('MyHttp', [
    "$http",
    "$rootScope",
function($http, $rootScope) {
    var emulator_path =  "/cache/";
    var local_database = false;
    var emulator = false;

    var genOptions = function(options) {
        var obj = {},
            i;
        if (obj) {
            for (i in options) {
                obj[i] = options[i];
            }
        }

        return obj;
    },

    genMAURL = function() {
        return 'jsonrpc';
    };

    this.post = function(obj) { //url, data, options) {
        var options = genOptions(obj.options),
            data = "",
            url = "",
            actm = "GET",
            popRPCResonsepAlert = false;

        if (obj.method) {
            data = {jsonrpc: "2.0", method: obj.method, params: (obj.params || "")};
        }

        if ((!local_database && !emulator && obj.method) || obj.forcedUsingPost === true) {
            actm = "POST";
            options['data'] = JSON.stringify(data);
        } else {
            if (emulator && obj.method) {
                url = emulator_path + obj.method + ".json";
            } else if (local_database || !obj.method) {
                url =  obj.url;
            } else {
                url = genMAURL();
            }
        }

        if (!url) {
            url = genMAURL();
        }

        options['url'] = '../'+ url;
        
        if (obj.timeout){
            options['timeout'] = obj.timeout || undefined;
        }

        options['method'] = actm;

        var MyHttpPromise = $http(options).
            success(function(data, status, headers, config, statusText) {
                var cbk = function() {
                    if(_.isFunction(obj.success)) {
                        obj.success({
                            data: data,
                            'status': status,
                            headers: headers,
                            config: config,
                            statusText: statusText
                        });
                    }
                };

                cbk();
            }).
            error(function(data, status, headers, config, statusText) {
                // HTTP status code 401 need redirect to logout

                var cbk = function() {
                    if(_.isFunction(obj.error)) {
                        obj.error({
                            data: data,
                            'status': status,
                            headers: headers,
                            config: config,
                            statusText: statusText
                        });
                    }
                };

                cbk();
            });

        return MyHttpPromise;
    };
}]);

app.controller('packetCaptureCtrl', [
    '$scope',
    'MyHttp',
    '$q',
function($scope, MyHttp, $q) {
    var scope = $scope;
    var exist = false;
    var getVal = function(value, defstr) {
        return (value !== undefined ? value : defstr);
    };

    var getResp = function(resps, idx) {
        return (resps && resps[idx] && resps[idx].data && resps[idx].data.result) || {};
    };

    var getInterfaces = function() {
        return MyHttp.post({
            method: 'get_interface'
        });
    },

    procInterfaces = function(result) {
        if (!result) {
            result = {};
        }

        var interfaces = [];

        if (result['interfaces'] && result['interfaces']['interface']) {
            interfaces = result['interfaces']['interface'];
        }

        scope.model.ifs = [];

        angular.forEach(interfaces, function(intf) {
            if (intf['name'].match(/^WAN\d+($|\.d+$)/)) {
                scope.model.ifs.push({
                    id: intf['name'],
                    displayName: intf['name']
                });
            }
        });
    };

    var doPktCaptureResponse = function() {
        return MyHttp.post({
            method: 'action',
            params: {
                'rpc': 'pkt-capture-response'
            }
        });
    },
    procPktCaptureResponse = function(result) {
        if (!result) {
            result = {};
        }

        var output      = result['output'] || {},
            def_state   = 'idle';

        scope.model.file_name = getVal(output['file-name'], '');

        if (scope.model.file_name) {
            def_state = 'stopped';
        }

        scope.model.state           = getVal(output['state'], def_state);
        scope.model.interface_name  = getVal(output['interface-name'], scope.model.interface_name);
    };

    var doPktCaptureRequest = function(action) {
        var input;
        scope.model.errstr = '';

        input = {
            // 'job-id': '',
            'interface-name': scope.model.interface_name,
            'action': action
        };

        switch (action) {
            case 'stop':
                input['job-id'] = scope.model.job_id;
                break;
            case 'start':
            case 'clear':
                break;
            default:
                return false;
        }

        return MyHttp.post({
            method: 'action',
            params: {
                'rpc': 'pkt-capture-request',
                'input': input
            }
        });
    },

    procPktCaptureRequest = function(result, action) {
        if (!result) {
            result = {};
        }

        var output  = result['output'] || {},
            code    = getVal(output['code'], 1),
            errstr  = getVal(output['errstr'], 'pkt-capture-request rpc failure'),
            jobId   = getVal(output['job-id'], '');

        if (jobId) {
            scope.model.job_id = jobId;
        } else {
            scope.model.errstr = errstr;
        }
    };

    var getStatus = function(cbk) {
        $q.all([doPktCaptureResponse()]).then(function(resps) {
            procPktCaptureResponse(getResp(resps, 0));

            if (cbk) {
                cbk();
            }
        });
    };

    var init = function() {
        //$q.all([doPktCaptureResponse(), getInterfaces()]).then(function(resps) {
        $q.all([doPktCaptureResponse()]).then(function(resps) {
            procPktCaptureResponse(getResp(resps, 0));
            scope.model.waiting = false;
            //procInterfaces(getResp(resps, 1));
            if (scope.model.state === 'capturing') {
                startPolling();
            }
        });

    };

    var updateDurationStr = function() {
        var duration = scope.model.duration,
            sec, min, hour;

        var toStr = function(num) {
            return num < 10 ? '0' + num : num;
        };

        if (scope.model.duration < 0) {
            scope.model.duration_str = '';
        } else {
            sec = duration % 60;

            duration = (duration - sec)/60;

            min = duration%60;

            duration = (duration-min)/60;
            hour = duration/24;

            scope.model.duration_str = toStr(hour) + ":" + toStr(min) + ":" + toStr(sec);
        }
    };

    var pollingId   = undefined,
        durationId  = undefined;

    var startDurationTimer = function() {
        durationId = setInterval(function() {
            scope.model.duration = scope.model.duration + 1;
            updateDurationStr();
        }, 1000);
    },

    stopDurationTimer = function() {
        if (durationId !== undefined) {
            clearInterval(durationId);
            durationId = undefined;
        }

        scope.model.duration = -1;
    };

    var startPolling = function() {
        stopPolling();

        pollingId = setTimeout(function() {
            pollingId = undefined;

            getStatus(function() {
                switch (scope.model.state) {
                    case 'capturing':
                        if (!exist) {
                            startPolling();
                        }
                        break;
                    case 'stopped':
                    case 'idle':
                    default:
                        stopDurationTimer();
                        break;

                }
            });
        }, 1000);
    },

    stopPolling = function() {
        if (pollingId !== undefined) {
            clearTimeout(pollingId);
            pollingId = undefined;
        }
    };
    
    scope.model = {
        state       : 'idle',    // stopped, capturing, idle
        job_id      : -1,
        file_name   : '',
        errstr      : '',
        waiting     : true,
        duration    : -1,
        duration_str: '',
        ifs         : [{id: 'WAN1', displayName: 'WAN1'}, {id: 'WAN2', displayName: 'WAN2'}, {id: 'LAN', displayName: 'LAN'}],
        interface_name: 'WAN1'
    };

    scope.funs = {
        start: function() {
            scope.model.waiting = true;
            $q.all([doPktCaptureRequest('start')]).then(function(resps) {
                stopDurationTimer();
                scope.model.duration = 0;
                startDurationTimer();
                updateDurationStr();

                procPktCaptureRequest(getResp(resps, 0), 'start');
                getStatus(function() {
                    scope.model.waiting = false;
                    if (scope.model.state === 'capturing') {
                        exist = false;
                        startPolling();
                    }
                });
            });
        },

        stop: function() {
            scope.model.waiting = true;
            $q.all([doPktCaptureRequest('stop')]).then(function(resps) {
                procPktCaptureRequest(getResp(resps, 0), 'stop');

                getStatus(function() {
                    scope.model.waiting = false;
                    if (scope.model.state === 'stopped') {
                        exist = true;
                        stopDurationTimer();
                        stopPolling();
                    }
                });
            });
        },

        clear: function() {
            scope.model.waiting = true;
            $q.all([doPktCaptureRequest('clear')]).then(function(resps) {
                procPktCaptureRequest(getResp(resps, 0), 'clear');
                getStatus(function() {
                    scope.model.waiting = false;
                });
            });
        },

        exportfile: function() {
            var download_save_to2 = function(url, savename, type) {
                var deferred = $q.defer(),
                x = new XMLHttpRequest(),
                path = document.location.origin + url;

                x.open("GET", path, true);
                x.responseType = 'blob';

                x.onload = function(e) {
                    if (x.status === 200) {
                        download(x.response, savename, type);
                        deferred.resolve({
                            status: this.status,
                            event: e
                        });
                    } else {
                        deferred.reject({
                            status: this.status,
                            event: e
                        });
                    }
                };

                x.send(null);

                return deferred.promise;
            };

            var path = scope.model.file_name,
                name = path.split('/');

            if (name) {
                name = name[name.length-1];
            } else {
                name = scope.model.interface_name + '_packet.pcap';
            }

            download_save_to2(path, name, "application/octet-stream");
        }
    };

    init();

    scope.$on('$destroy', function() {
        stopPolling();
        stopDurationTimer();
        exist = true;
    });
}]);
