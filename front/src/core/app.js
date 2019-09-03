import axios from 'axios'
import {Logger} from './logger'

import {timezones} from './timezones'

export class Application {
    constructor() {
        this.baseApiServer =  `http://10.10.10.25:10023`;
        this.apiVersionUrl = `/api/v2`;
        // axios.defaults.headers.common['X-Access-Token'] = 'GUEST_TOKEN';
        this.log = new Logger();
        this.cli = axios.create({
            headers: {
                common: {
                    'Authorization': 'X-Access-Token GUEST_TOKEN',
                },
            },
        });
    }

    request(method = 'get', path = '', data) {
        this.log.debug(`request[${method}] to ${path}`);
        return this.cli({
            method,
            url: `${this.baseApiServer}${this.apiVersionUrl}${path}`,
            data
        }).catch((e) => {
            if (e.response && e.response.data instanceof Object) {
                this.log.error(`request[${method}] to ${path} error: `, JSON.stringify(e.response.data));
                throw new Error(`${e.response.data.message} \nDetail: ${e.response.data.detailed_error}`)
            } else {
                this.log.error(`request[${method}] to ${path} error: `, e.message);
                throw e;
            }
        })
    }

    getTimezones() {
        return timezones
    }
}