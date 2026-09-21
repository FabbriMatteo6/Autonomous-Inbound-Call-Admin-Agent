-- ==============================================================================
-- Supabase Cloud Schema: Inbound Call Admin Agent
-- ==============================================================================
-- Target Tables:
-- 1. products_sku: Product catalog, SKU identifiers, stock levels, pricing.
-- 2. call_logs: Audit log of inbound telephony calls, summaries, transcripts.
-- ==============================================================================

-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. PRODUCTS & SKU CATALOG TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products_sku (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sku VARCHAR(64) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100) NOT NULL DEFAULT 'General',
    price NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Performance Indexes for Voice Agent Sub-Second Lookups
CREATE INDEX IF NOT EXISTS idx_products_sku_lookup ON public.products_sku (sku);
CREATE INDEX IF NOT EXISTS idx_products_sku_lower ON public.products_sku (LOWER(sku));
CREATE INDEX IF NOT EXISTS idx_products_sku_active ON public.products_sku (is_active);
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON public.products_sku USING gin (to_tsvector('english', name));

-- Automatic updated_at trigger function
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_products_sku_updated_at ON public.products_sku;
CREATE TRIGGER trg_products_sku_updated_at
    BEFORE UPDATE ON public.products_sku
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- ------------------------------------------------------------------------------
-- 2. INBOUND CALL LOGS & TRANSCRIPTS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.call_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    call_id VARCHAR(128) NOT NULL UNIQUE,
    caller_phone VARCHAR(64),
    duration_seconds INTEGER DEFAULT 0,
    status VARCHAR(64) NOT NULL DEFAULT 'completed',
    intent VARCHAR(64) DEFAULT 'general_inquiry',
    summary TEXT,
    transcript TEXT,
    tools_used JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Indexes for Call Reporting and Analytics
CREATE INDEX IF NOT EXISTS idx_call_logs_call_id ON public.call_logs (call_id);
CREATE INDEX IF NOT EXISTS idx_call_logs_created_at ON public.call_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_logs_intent ON public.call_logs (intent);

-- ------------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE public.products_sku ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_logs ENABLE ROW LEVEL SECURITY;

-- Allow authenticated / service_role full control
DROP POLICY IF EXISTS "Service role full access on products_sku" ON public.products_sku;
CREATE POLICY "Service role full access on products_sku"
    ON public.products_sku
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Allow public read access to active products for catalog search
DROP POLICY IF EXISTS "Public read access on active products_sku" ON public.products_sku;
CREATE POLICY "Public read access on active products_sku"
    ON public.products_sku
    FOR SELECT
    USING (is_active = true);

-- Allow service_role full control on call_logs
DROP POLICY IF EXISTS "Service role full access on call_logs" ON public.call_logs;
CREATE POLICY "Service role full access on call_logs"
    ON public.call_logs
    FOR ALL
    USING (true)
    WITH CHECK (true);
