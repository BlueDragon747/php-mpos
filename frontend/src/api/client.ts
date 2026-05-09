// Same-origin fetch wrapper for MPOS JSON API.
//
// MPOS API endpoints live at index.php?page=api&action=<X>, are stateless,
// and authenticate via the api_key query parameter. Session cookie is
// optional (used only if you call non-api endpoints). All callers are
// same-origin so cookies attach automatically when needed.

import type { DashboardDataResponse, UserWorkersResponse, UserBalanceResponse } from './types';

export interface ApiCallOptions {
  apiKey: string;
  userId: number;
}

const API_BASE = '/index.php';

async function callApi<T>(action: string, params: Record<string, string | number>): Promise<T> {
  const search = new URLSearchParams({
    page: 'api',
    action,
    ...Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)])),
  });
  const url = `${API_BASE}?${search.toString()}`;
  const res = await fetch(url, { credentials: 'same-origin' });
  if (!res.ok) {
    throw new Error(`MPOS API ${action} failed: HTTP ${res.status}`);
  }
  // MPOS sometimes returns HTML (rate-limit page, login page, etc.)
  // with a 200 status. Surface the actual body excerpt so we can see
  // which redirect tripped instead of getting a generic JSON parse
  // error. Log full body to console; throw a short Error message.
  const text = await res.text();
  try {
    return JSON.parse(text) as T;
  } catch (err) {
    const ct = res.headers.get('content-type') ?? 'unknown';
    const head = text.slice(0, 200).replace(/\s+/g, ' ').trim();
    // eslint-disable-next-line no-console
    console.error(`[mpos-api] ${action} returned non-JSON (content-type=${ct})\n--- body head ---\n${text.slice(0, 1000)}\n--- end ---`);
    throw new Error(`MPOS API ${action} returned non-JSON [${ct}]: ${head}`);
  }
}

export const api = {
  getDashboardData(opts: ApiCallOptions): Promise<DashboardDataResponse> {
    return callApi('getdashboarddata', { api_key: opts.apiKey, id: opts.userId });
  },
  getUserWorkers(opts: ApiCallOptions): Promise<UserWorkersResponse> {
    return callApi('getuserworkers', { api_key: opts.apiKey, id: opts.userId });
  },
  getUserBalance(opts: ApiCallOptions): Promise<UserBalanceResponse> {
    return callApi('getuserbalance', { api_key: opts.apiKey, id: opts.userId });
  },
};
