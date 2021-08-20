import adapter from 'axios/lib/adapters/http';
import axios from "axios";
import { config } from "./utils/config";
import { testData } from "./utils/test-data";

describe('MHS Route connection', () => {
    it('should return expected asid from MHS Route', async () => {
        const { repoOdsCode, repoAsid } = testData[config.nhsEnvironment];
        const serviceId = 'urn:nhs:names:services:gp2gp:RCMR_IN010000UK05';

        const mhsRouteUrl = `https://route.mhs.${config.nhsEnvironment}.non-prod.patient-deductions.nhs.uk`;
        const baseUrl = mhsRouteUrl.replace(/\/$/, '');
        const url = `${baseUrl}/routing`;

        const res = await axios.get(url, {
            params: {
                'org-code': repoOdsCode,
                'service-id': serviceId
            },
            adapter
        });

        expect(res.data.uniqueIdentifier[0]).toEqual(repoAsid);
    })
})