import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import styles from "./Login.module.css";

interface LoginViewProps {
  isOtpMode: boolean;
  username: string;
  password: string;
  otp: string;
  loading: boolean;
  error: string;
  onUsernameChange: (value: string) => void;
  onPasswordChange: (value: string) => void;
  onOtpChange: (value: string) => void;
  onSubmit: (e: React.FormEvent) => void;
  onCancel: () => void;
}

export default function LoginView({
  isOtpMode,
  username,
  password,
  otp,
  loading,
  error,
  onUsernameChange,
  onPasswordChange,
  onOtpChange,
  onSubmit,
  onCancel,
}: LoginViewProps) {
  return (
    <div className={styles.loginContainer}>
      <Card className="w-full max-w-md">
        <CardHeader>
          <div className={styles.brandBadge}>
            <div className={styles.logoBox}>P</div>
            <span className="font-semibold text-lg tracking-tight">PromoHub ERP</span>
          </div>
          <CardTitle className="text-center text-2xl">
            {isOtpMode ? "Verifikasi Perangkat" : "Masuk ke PromoHub"}
          </CardTitle>
          {isOtpMode && (
            <CardDescription className="text-center text-orange-600">
              Perangkat baru terdeteksi. Masukkan kode OTP yang dikirim ke perangkat Anda.
            </CardDescription>
          )}
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="space-y-4">
            {!isOtpMode ? (
              <>
                <div className="space-y-2">
                  <Label htmlFor="username">Username</Label>
                  <Input
                    id="username"
                    value={username}
                    onChange={(e) => onUsernameChange(e.target.value)}
                    placeholder="Masukkan username Keycloak"
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="password">Password</Label>
                  <Input
                    id="password"
                    type="password"
                    value={password}
                    onChange={(e) => onPasswordChange(e.target.value)}
                    placeholder="Masukkan password"
                    required
                  />
                </div>
              </>
            ) : (
              <div className="space-y-2">
                <Label htmlFor="otp">Kode OTP</Label>
                <Input
                  id="otp"
                  type="text"
                  maxLength={6}
                  value={otp}
                  onChange={(e) => onOtpChange(e.target.value)}
                  placeholder="Masukkan 6 digit OTP"
                  required
                />
              </div>
            )}

            {error && <p className="text-sm text-red-500">{error}</p>}

            {!isOtpMode ? (
              <Button type="submit" className="w-full" disabled={loading}>
                {loading ? "Memproses..." : "Masuk dengan Keycloak"}
              </Button>
            ) : (
              <div className="flex space-x-2">
                <Button
                  type="button"
                  variant="outline"
                  className="w-1/2"
                  onClick={onCancel}
                  disabled={loading}
                >
                  Batal
                </Button>
                <Button type="submit" className="w-1/2" disabled={loading}>
                  {loading ? "Memproses..." : "Verifikasi OTP"}
                </Button>
              </div>
            )}
          </form>

          <div className={styles.demoBanner}>
            <Link href="/dashboard/overview" className={styles.demoLink}>
              Buka Dashboard PromoHub Langsung →
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
