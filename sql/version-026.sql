--
-- Track when account storage was last cleaned.
--
ALTER TABLE GarbageCollectionTable ADD COLUMN last_cleanup_time_t INTEGER DEFAULT NULL;
