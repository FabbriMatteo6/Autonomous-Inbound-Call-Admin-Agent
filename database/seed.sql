-- ==============================================================================
-- Supabase Cloud Seed Data: Inbound Call Admin Agent
-- ==============================================================================
-- Sample realistic catalog for an automotive & service care business (Acme Auto Care)
-- and initial call logs for testing audit and retrieval.
-- ==============================================================================

-- 1. Insert Sample Product & Service SKUs
INSERT INTO public.products_sku (sku, name, description, category, price, currency, stock_quantity, is_active)
VALUES
    (
        'SKU-1001',
        'Full Synthetic Oil Change 5W-30',
        'Premium 5-quart full synthetic motor oil replacement including OEM oil filter, fluid top-off, and 21-point vehicle safety inspection.',
        'Maintenance',
        69.99,
        'USD',
        18,
        true
    ),
    (
        'SKU-1002',
        'Conventional Oil Change 5W-20',
        'Standard 5-quart conventional motor oil change with new filter replacement and fluid inspection.',
        'Maintenance',
        39.99,
        'USD',
        25,
        true
    ),
    (
        'SKU-1003',
        'Front Ceramic Brake Pad Replacement',
        'Premium low-dust ceramic brake pads installation for front axle, including rotor inspection and hardware lubrication.',
        'Brakes',
        149.99,
        'USD',
        8,
        true
    ),
    (
        'SKU-1004',
        'Tire Rotation and Computerized Balance',
        'Four-wheel tire rotation, pressure adjustment, and high-speed computerized wheel balancing.',
        'Tires',
        49.99,
        'USD',
        40,
        true
    ),
    (
        'SKU-1005',
        'Comprehensive Multi-Point Safety Inspection',
        'Complete 50-point diagnostic check covering suspension, steering, brakes, exhaust, battery, and fluid conditions with digital report.',
        'Diagnostics',
        29.99,
        'USD',
        50,
        true
    ),
    (
        'SKU-1006',
        'Cabin Air Filter Replacement',
        'High-efficiency particulate cabin air filter replacement removing dust, pollen, and allergens from AC/heating system.',
        'Filters',
        34.99,
        'USD',
        12,
        true
    ),
    (
        'SKU-1007',
        'Engine Air Filter Replacement',
        'High-flow engine air filter replacement to restore engine combustion efficiency and fuel economy.',
        'Filters',
        29.99,
        'USD',
        15,
        true
    ),
    (
        'SKU-1008',
        'Battery Health Diagnostic & Replacement',
        'Heavy-duty 12V automotive battery replacement including terminal cleaning, testing, and old battery environmental recycling.',
        'Electrical',
        179.99,
        'USD',
        6,
        true
    )
ON CONFLICT (sku) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    price = EXCLUDED.price,
    currency = EXCLUDED.currency,
    stock_quantity = EXCLUDED.stock_quantity,
    is_active = EXCLUDED.is_active,
    updated_at = timezone('utc'::text, now());

-- 2. Insert Sample Historical Call Logs
INSERT INTO public.call_logs (call_id, caller_phone, duration_seconds, status, intent, summary, transcript, tools_used)
VALUES
    (
        'call_sample_test_001',
        '+15550192834',
        112,
        'completed',
        'sku_inquiry',
        'Customer inquired about Full Synthetic Oil Change (SKU-1001) price and stock availability. Verified 18 slots in stock at $69.99.',
        'Caller: Hi, do you have synthetic oil changes today?\nAgent: Yes, we have our Full Synthetic Oil Change package in stock for $69.99 with 18 slots open.\nCaller: Great, thanks!',
        '["lookup_sku"]'::jsonb
    ),
    (
        'call_sample_test_002',
        '+15550198821',
        168,
        'completed',
        'appointment_booking',
        'Customer requested appointment for brake inspection tomorrow at 3:00 PM. Checked calendar and confirmed reservation.',
        'Caller: Can I book an appointment for tomorrow afternoon?\nAgent: Yes, 3:00 PM is available. What is your name?\nCaller: John Doe.\nAgent: Confirmed for 3:00 PM tomorrow!',
        '["check_availability", "book_appointment"]'::jsonb
    )
ON CONFLICT (call_id) DO NOTHING;
