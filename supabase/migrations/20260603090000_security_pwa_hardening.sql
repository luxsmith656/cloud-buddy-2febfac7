-- Security and PWA hardening after the PWA/offline update.

REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated;

-- Keep browser-uploaded inventory images safe. Older migrations allowed SVG/GIF/BMP;
-- the app only accepts compressed PNG/JPG/WEBP and storage should match that.
UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp'],
    file_size_limit = 5242880
WHERE id = 'images';
