import { EventTarget, Event, defineEventAttribute } from 'event-target-shim';
import { NativeModules } from 'react-native';

import { addListener } from './EventEmitter';
import getDisplayMedia from './getDisplayMedia';
import getUserMedia from './getUserMedia';

const { WebRTCModule } = NativeModules;

type MediaDevicesEventMap = {
    devicechange: Event<'devicechange'>
}

class MediaDevices extends EventTarget<MediaDevicesEventMap> {
    constructor() {
      super();
      this._registerEvents();
    }

    /**
     * W3C "Media Capture and Streams" compatible {@code enumerateDevices}
     * implementation.
     */
    enumerateDevices() {
        return new Promise(resolve => WebRTCModule.enumerateDevices(resolve));
    }

    /**
     * W3C "Screen Capture" compatible {@code getDisplayMedia} implementation.
     * See: https://w3c.github.io/mediacapture-screen-share/
     *
     * @returns {Promise}
     */
    getDisplayMedia() {
        return getDisplayMedia();
    }

    /**
     * W3C "Media Capture and Streams" compatible {@code getUserMedia}
     * implementation.
     * See: https://www.w3.org/TR/mediacapture-streams/#dom-mediadevices-enumeratedevices
     *
     * @param {*} constraints
     * @returns {Promise}
     */
    getUserMedia(constraints) {
        return getUserMedia(constraints);
    }

    _registerEvents(): void {
        console.log('MediaDevices _registerEvents invoked');
        WebRTCModule.startMediaDevicesEventMonitor();
        addListener(this,'mediaDevicesOnDeviceChange', () => {
            console.log('MediaDevices => mediaDevicesOnDeviceChange');
            // @ts-ignore
            this.dispatchEvent(new RTCEvent('devicechange'));
        });
    }
}

/**
 * Define the `onxxx` event handlers.
 */
const proto = MediaDevices.prototype;

defineEventAttribute(proto, 'devicechange');


export default new MediaDevices();
