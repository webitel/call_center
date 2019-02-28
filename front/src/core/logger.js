
export class Logger {
    constructor(logLvl = 0) {
        this.logLvl = logLvl
    }

    debug() {
        console.debug.apply(null, arguments)
    }
    error() {
        console.error.apply(null, arguments)
    }
    warn() {
        console.warn.apply(null, arguments)
    }
}