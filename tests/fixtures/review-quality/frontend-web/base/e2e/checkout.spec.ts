import { expect, test } from '@playwright/test';

test('home page lists products and links to details', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: 'Desk lamp' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Desk lamp');
});
