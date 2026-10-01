/**
 * Auth surface. /auth/status doubles as the reachability probe, and an
 * unauthenticated server simply returns an empty token.
 */
import { ApiClient } from '../net/ApiClient';
import { AuthStatus, LoginRequest, LoginResponse } from '../model/Dtos';
import { ApiPath } from '../core/Wire';

export class AuthApi {
  private readonly client: ApiClient;

  constructor(client: ApiClient) {
    this.client = client;
  }

  async status(): Promise<AuthStatus> {
    const raw = await this.client.get(ApiPath.AUTH_STATUS);
    return JSON.parse(raw) as AuthStatus;
  }

  /** expires_in 0 asks for a non-expiring token, so the phone rarely re-logins. */
  async login(username: string, password: string): Promise<LoginResponse> {
    const body = new LoginRequest();
    body.username = username;
    body.password = password;
    body.expires_in = 0;
    const raw = await this.client.post(ApiPath.AUTH_LOGIN, JSON.stringify(body));
    return JSON.parse(raw) as LoginResponse;
  }
}
