import { expect, test } from '@playwright/test';

test('home page lists products and links to details', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: 'Desk lamp' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Desk lamp');
});

test('catalog search narrows the product list', async ({ page }) => {
  await page.goto('/');
  await page.getByPlaceholder('Search products').fill('floor lamp');
  await expect(page.getByRole('link', { name: 'Floor lamp' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Desk lamp' })).toHaveCount(0);
});

test('shopper can add a product to the cart from the product page', async ({ page }) => {
  await page.goto('/products/1');
  await page.locator('main.product > div:nth-child(7) > div:nth-child(1)').click();
  await expect(page.getByRole('status')).toHaveText('Added to your cart.');
});
