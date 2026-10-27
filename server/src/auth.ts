import jwt from 'jsonwebtoken';

export interface TokenPayload { sub: string }

export class Tokens {
  constructor(private secret: string) {}
  sign(userId: string): string {
    return jwt.sign({ sub: userId }, this.secret, { algorithm: 'HS256', expiresIn: '60d' });
  }
  verify(token: string): string | null {
    try {
      const p = jwt.verify(token, this.secret, { algorithms: ['HS256'] }) as TokenPayload;
      return typeof p.sub === 'string' ? p.sub : null;
    } catch {
      return null;
    }
  }
}

/** Verifies a Firebase ID token obtained by the app after Google sign-in. */
export interface GoogleVerifier {
  verify(idToken: string): Promise<{ uid: string; name: string | null }>;
}

export async function createFirebaseVerifier(projectId: string): Promise<GoogleVerifier> {
  const { initializeApp, getApps } = await import('firebase-admin/app');
  const { getAuth } = await import('firebase-admin/auth');
  const app = getApps()[0] ?? initializeApp({ projectId });
  const auth = getAuth(app);
  return {
    async verify(idToken: string) {
      const t = await auth.verifyIdToken(idToken, true);
      const provider = t.firebase?.sign_in_provider;
      if (provider !== 'google.com') throw new Error('not_google');
      return { uid: t.uid, name: typeof t.name === 'string' ? t.name : null };
    },
  };
}
