import axios from 'axios'
import {Logger} from './logger'

import {timezones} from './timezones'

export class Application {
    constructor() {
        this.baseApiServer =  `http://10.10.10.25:10023`;
        this.log = new Logger()
    }

    request(method = 'get', path = '', data) {
        this.log.debug(`request[${method}] to ${path}`);
        return axios({
            method,
            url: `${this.baseApiServer}/${path}`,
            data
        }).catch((e) => {
            this.log.error(`request[${method}] to ${path} error: `, e.message);
            throw e;
        })
    }

    getTimezones() {
        return timezones
    }
}