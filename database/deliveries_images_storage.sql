-- 1. Création du bucket "deliveries_images" (public)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('deliveries_images', 'deliveries_images', true);

-- 2. Politique pour permettre l'upload d'images (utilisateurs authentifiés uniquement)
DROP POLICY IF EXISTS "Allow authenticated uploads" ON storage.objects;
CREATE POLICY "Allow authenticated uploads" 
ON storage.objects 
FOR INSERT 
TO authenticated 
WITH CHECK (bucket_id = 'deliveries_images');

-- 3. Politique pour permettre la lecture publique des images (tout le monde peut voir)
DROP POLICY IF EXISTS "Allow public read access" ON storage.objects;
CREATE POLICY "Allow public read access" 
ON storage.objects 
FOR SELECT 
TO public 
USING (bucket_id = 'deliveries_images');

-- 4. (Optionnel) Politique pour permettre la suppression/mise à jour par le propriétaire (celui qui a uploadé)
DROP POLICY IF EXISTS "Allow owner to update/delete" ON storage.objects;
CREATE POLICY "Allow owner to update/delete" 
ON storage.objects 
FOR ALL 
TO authenticated 
USING (bucket_id = 'deliveries_images' AND auth.uid() = owner);