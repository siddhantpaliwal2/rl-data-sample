import { describe, expect, test } from 'bun:test';
import {
	formatAddress,
	formatCompactNumber,
	formatCryptoAmount,
	formatCurrency,
	formatPercentage,
	formatPhoneNumber,
	formatRelativeTime,
	isValidEmail,
	isValidPhone,
	truncateText,
} from '../lib/formatters';

describe('native trading display formatters', () => {
	test('formats currencies with the requested currency and precision', () => {
		expect(formatCurrency(1234.5)).toBe('$1,234.50');
		expect(formatCurrency(1234, 'MUR', 0)).toContain('1,234');
	});

	test('formats compact market values across thresholds', () => {
		expect(formatCompactNumber(999)).toBe('999.00');
		expect(formatCompactNumber(1_500)).toBe('1.50K');
		expect(formatCompactNumber(2_500_000)).toBe('2.50M');
		expect(formatCompactNumber(3_000_000_000)).toBe('3.00B');
	});

	test('formats positive, negative, and unsigned percentage changes', () => {
		expect(formatPercentage(1.2)).toBe('+1.20%');
		expect(formatPercentage(-1.2, 1)).toBe('-1.2%');
		expect(formatPercentage(1.2, 2, false)).toBe('1.20%');
	});

	test('selects crypto precision that preserves small balances', () => {
		expect(formatCryptoAmount(0.00001234, 'BTC')).toBe('0.00001234 BTC');
		expect(formatCryptoAmount(0.125, 'ETH')).toBe('0.1250 ETH');
		expect(formatCryptoAmount(12.5, 'SOL')).toBe('12.50 SOL');
	});

	test('truncates text only when it exceeds the requested length', () => {
		expect(truncateText('AAPL', 4)).toBe('AAPL');
		expect(truncateText('Alphabet', 5)).toBe('Alpha...');
	});

	test('shortens wallet addresses without losing the visible ends', () => {
		expect(formatAddress('0x1234567890abcdef', 4)).toBe('0x12...cdef');
		expect(formatAddress('short', 4)).toBe('short');
	});

	test('validates user email and phone input before API submission', () => {
		expect(isValidEmail('investor@example.com')).toBe(true);
		expect(isValidEmail('investor.example.com')).toBe(false);
		expect(isValidPhone('+230 5123 4567')).toBe(true);
		expect(isValidPhone('12345')).toBe(false);
	});

	test('formats ten-digit phones and preserves other international inputs', () => {
		expect(formatPhoneNumber('5551234567')).toBe('(555) 123-4567');
		expect(formatPhoneNumber('+230 5123 4567')).toBe('+230 5123 4567');
	});

	test('renders relative recency across minute, hour, day, and old-data boundaries', () => {
		const now = Date.now();
		expect(formatRelativeTime(now - 30_000)).toBe('Just now');
		expect(formatRelativeTime(now - 3 * 60_000)).toBe('3m ago');
		expect(formatRelativeTime(now - 2 * 60 * 60_000)).toBe('2h ago');
		expect(formatRelativeTime(now - 3 * 24 * 60 * 60_000)).toBe('3d ago');
		expect(formatRelativeTime(now - 8 * 24 * 60 * 60_000)).toMatch(/^[A-Z][a-z]{2} \d{1,2}$/);
	});
});
