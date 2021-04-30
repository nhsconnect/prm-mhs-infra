import adapter from 'axios/lib/adapters/http';
import axios from "axios";
import { config } from "./utils/config";

describe('MHS Inbound connection', () => {
  it('should connect to MHS Inbound', async () => {
    const { mhsInboundUrl } = config;
    const url = `${mhsInboundUrl}/healthcheck`;
    const res = await axios.get(url, { adapter });

    expect(res.status).toBe(200);
  })
})