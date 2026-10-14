local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Warrior-Arms','Priest-Holy','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Druid-Balance','Shaman-Elemental','Mage-Arcane','Monk-Windwalker','Rogue-Assassination','DemonHunter-Vengeance','Druid-Feral','Monk-Brewmaster','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Paladin-Protection','Monk-Mistweaver','DemonHunter-Havoc','Paladin-Retribution','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Hunter-Marksmanship','Warrior-Protection','Priest-Shadow','Druid-Guardian','Evoker-Devastation','Mage-Fire','Priest-Discipline',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAAANQAECgUIEwAAAA==.',
Ad='Ado:BAAANQAECgUICAAAAA==.Adversity:BAABNQAFFH8FAAIBAAMKBRAHJQDTAAABAAMKBRAHJQDTAAAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgcICgAAAA==.',
Ai='Aiolii:BAAANQAECgQICgAAAA==.',
Ak='Akiras:BAAANQABCgYIDAAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUICgABNQAECggIHQACADATAA==.Alyndrya:BAABNQAECn8qAAIDAAgKWxKIKAD8AQADAAgKWxKIKAD8AQAAAA==.',
Am='Amithralia:BAABNQAECn8fAAIEAAcKECESFgCRAgAEAAcKECESFgCRAgAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQAECgEIAQABNQAECgUIBwAFAAAAAA==.Anzarna:BAAANQADCggIIQABNQAECgIIAgAFAAAAAA==.',
Ao='Aohikari:BAAANQAECgMIBQABNQAFFAcIGgAGAIkYAA==.',
Ap='Aprigity:BAAANQAECgQIBQAAAA==.',
Aq='Aquaten:BAAANQAECgQIDgAAAA==.',
Ar='Arashinigon:BAABNQAECn8VAAMEAAYKwhR2QAAdAQAEAAUKqBF2QAAdAQAHAAEK+w21qgA9AAAAAA==.Arceus:BAAANQAECgQIBAAAAA==.Arick:BAAANQAECgYIEwAAAA==.Ark:BAABNQAECn8/AAMGAAkK+yYRAAAFBAAGAAkK+yYRAAAFBAAIAAEKAADrFAFdAAAAAA==.',
As='Astrofax:BAAANQABCggIDQAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAAANQAECgYICgAAAA==.',
Ax='Axon:BAABNQAECn8fAAIJAAcKMAinEgFpAQAJAAcKMAinEgFpAQAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAAANQAECgQIDgAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAABNQAECn8oAAMGAAgKbhn/OwBtAgAGAAgKbhn/OwBtAgAIAAEKAABPVAEgAAAAAA==.Battlebot:BAAANQAECgUIDAAAAA==.',
Be='Beet:BAABNQAECn8gAAIKAAgKFCEJDgD7AgAKAAgKFCEJDgD7AgAAAA==.Belgaron:BAAANQAECgQIBAABNQAECgcIJgAKADAXAA==.Belitha:BAABNQAECn8fAAIDAAkK3B7JDAAUAwADAAkK3B7JDAAUAwAAAA==.Belmaris:BAABNQAECn8bAAILAAcKexqmLgAkAgALAAcKexqmLgAkAgAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgUICgAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECgQIBAAFAAAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgQIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECn8eAAIMAAcK2httCQBOAgAMAAcK2httCQBOAgAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECn8mAAINAAgKYx9XCADNAgANAAgKYx9XCADNAgAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAABNQAECn8cAAIOAAYKISEVDABCAgAOAAYKISEVDABCAgAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAECgcIEAAFAAAAAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgIIAwAAAA==.Brisket:BAAANQADCggIGwAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAABNQAECn8XAAIPAAcKDh74PwBiAgAPAAcKDh74PwBiAgAAAA==.Bubbs:BAAANQADCgQIBAABNQAECggIHwAKABkkAA==.Buckme:BAABNQAECn8lAAIQAAkKxhqAMgDSAgAQAAkKxhqAMgDSAgAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAcIEwARAKIiAA==.Busen:BAAANQADCggIFgAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECn8dAAMSAAkKfxEKUgBcAgASAAkKfxEKUgBcAgARAAEKNxG3cgA7AAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQAECgQICgAAAA==.Caralhan:BAAANQAECgQICAAAAA==.Castelo:BAAANQADCggICAAAAA==.',
Ce='Cedra:BAABNQAECn83AAMJAAkK8SP8FwB0AwAJAAkK1iP8FwB0AwATAAEKniaqMQBxAAAAAA==.Cegeo:BAABNQAECn8dAAIRAAcKNRFMEQDtAQARAAcKNRFMEQDtAQAAAA==.Celari:BAAANQAECgEIAQAAAA==.',
Ch='Cheepdeeps:BAABNQAECn8lAAIBAAcKBxnEiwD7AQABAAcKBxnEiwD7AQAAAA==.Chelea:BAAANQADCgUIBQAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQAECgUICAAAAA==.Cirdle:BAABNQAECn8aAAIQAAcK7xBwjwDnAQAQAAcK7xBwjwDnAQAAAA==.',
Co='Cobalt:BAECNQAFFH8GAAISAAIKUBNWLgCfAAASAAIKUBNWLgCfAAA1AAQKfyMAAhIACQoLH+cfAAIDABIACQoLH+cfAAIDAAE1AAUUBQgFABIAxA8A.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAABNQAECn8bAAIIAAcKcgMhzwDwAAAIAAcKcgMhzwDwAAAAAA==.Crucifixea:BAABNQAECn8ZAAMPAAgKoBVRRwBHAgAPAAgKoBVRRwBHAgAUAAcKSRHmLgBjAQAAAA==.Cruxsader:BAAANQADCggIEAAAAA==.Crystyl:BAAANQAECgUICAAAAA==.',
Ct='Ctesias:BAAANQADCgYIBgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAQIBAAFAAAAAA==.Cute:BAAANQAECgYIBgABNQAECgcIEAAFAAAAAA==.',
Cy='Cymoril:BAABNQAECn8mAAIBAAgK0Rv8agBNAgABAAgK0Rv8agBNAgAAAA==.',
Da='Daamass:BAAANQAECgIIAgAAAA==.Daddy:BAACNQAFFH8IAAIVAAIK+SZLBwDqAAAVAAIK+SZLBwDqAAA1AAQKf3oAAhUACQr3JgMAABsEABUACQr3JgMAABsEAAAA.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAAANQAECgYICgAAAA==.Darkcarnival:BAABNQAECn8aAAISAAcKAxawhADWAQASAAcKAxawhADWAQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgkJJQAGAHEjAA==.Darthraider:BAAANQADCgQIBAAAAA==.Dasnotgood:BAAANQADCggIHwAAAA==.',
De='Deemon:BAABNQAECn8ZAAMDAAcKHRdaMgCqAQADAAYK8hlaMgCqAQAWAAIKxwthfgB2AAAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Denard:BAAANQADCgUIDQABNQADCggIGwAFAAAAAA==.Denarias:BAAANQADCgUJBQABNQAECgIIAgAFAAAAAA==.Denevien:BAAANQAECgUICwAAAA==.Desdemona:BAAANQAECgUICAAAAA==.Dethiaris:BAAANQAECgQIBgAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAAANQAECgcIDwAAAA==.',
Do='Dobutsu:BAAANQAECgcIDAAAAA==.Doomace:BAABNQAECn8sAAIXAAkKXBLOfQAqAgAXAAkKXBLOfQAqAgAAAA==.',
Dr='Draaka:BAAANQADCgYIDgAAAA==.Dragee:BAAANQAECgQIBAABNQAECgcIGQADAB0XAA==.Dragon:BAAANQAECgcIBwAAAA==.Driftyshaman:BAAANQADCggIHgAAAA==.Droopy:BAAANQAECgUIBQAAAA==.Dræghoule:BAAANQAECgUIBwAAAA==.',
Du='Durnik:BAAANQAECgcIDwABNQAECgcIJgAKADAXAA==.',
Dw='Dworflundgrn:BAAANQAECgYIEAAAAA==.',
Dy='Dyamí:BAABNQAECn8bAAIJAAcK+hAY2gDQAQAJAAcK+hAY2gDQAQAAAA==.',
['Dá']='Dánte:BAAANQAECgIIAgAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECn8qAAMEAAgKJwcQNgBmAQAEAAgKJwcQNgBmAQAHAAUK+xUPXQBZAQAAAA==.Eldiablo:BAAANQAECgMIBwAAAA==.Electric:BAAANQAECgQICQAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECn8hAAIJAAcK3gazEQFrAQAJAAcK3gazEQFrAQAAAA==.Elrythe:BAABNQAECn8zAAIQAAkKaBwSLQDlAgAQAAkKaBwSLQDlAgAAAA==.',
Er='Eraleth:BAAANQAECgUICAABNQAECgkJHwADANweAA==.',
Et='Etarnus:BAAANQADCggIDQAAAA==.',
Fa='Faben:BAAANQADCgUIBQAAAA==.Faced:BAAANQAECgUICwAAAA==.Fatalii:BAAANQAECgcICQAAAA==.',
Fe='Felebash:BAAANQAECgUICgAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECn8qAAIYAAkK0SRIAQCvAwAYAAkK0SRIAQCvAwAAAA==.Floofthulu:BAAANQAECgEIAQABNQAECgkJKgAYANEkAA==.Fluffalo:BAABNQAECn8hAAIIAAkKtCFCEQBjAwAIAAkKtCFCEQBjAwABNQAECgkJKgAYANEkAA==.',
Fo='Foxypocket:BAAANQAECgQICwAAAA==.',
Fr='Fredrickk:BAAANQAECgQIBwAAAA==.',
Fu='Furcas:BAAANQAECgIIAgAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgkJKgAYANEkAA==.Furrylight:BAAANQAECgEIAQABNQAECgkJHwAGAF8fAA==.Furryphase:BAABNQAECn8fAAMGAAkKXx/+HQDyAgAGAAkKXx/+HQDyAgAIAAEKAADwUgEhAAAAAA==.Fuzzington:BAAANQAECgYICwABNQAECgkJKgAYANEkAA==.Fuzzydunlop:BAAANQADCgMIAwAAAA==.',
Ga='Gaith:BAAANQAECgYIBgAAAA==.Galnier:BAAANQAECgIJBQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaur:BAABNQAECn8dAAIGAAgKXBL1bwC4AQAGAAgKXBL1bwC4AQAAAA==.',
Gr='Gripisrdy:BAABNQAECn8aAAQZAAcKNx2NOQA7AgAZAAYKjyCNOQA7AgAaAAYKVBlbSQCQAQAbAAIK2w8rpwCAAAAAAA==.',
Gu='Gunslingr:BAABNQAECn8jAAIcAAgKFSIjAwAIAwAcAAgKFSIjAwAIAwAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAABNQAECn8aAAMdAAkKuRueEgDMAgAdAAkKuRueEgDMAgAQAAUK7xNSxQByAQAAAA==.',
He='Headpats:BAAANQAFFAIIAgABNQAFFAQIBAAFAAAAAA==.Hearthisrdy:BAAANQADCggIDwAAAA==.Hexwhisper:BAAANQAECgQIBAAAAA==.Heycarlos:BAABNQAECn8zAAMaAAkKdiJdBgB6AwAaAAkKdiJdBgB6AwAZAAIKrwecywBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAcIGgAGAIkYAA==.Hikarishaman:BAACNQAFFH8aAAMGAAcKiRghCgCoAQAGAAUKDhYhCgCoAQAIAAQKmhshEgBGAQA1AAQKfyYAAwgACQpxHBdOADsCAAgACAq4GhdOADsCAAYACQqiGzBOACgCAAAA.Hime:BAAANQAECgYIEQAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAABNQAECn8WAAIZAAgKWhmAOQA7AgAZAAgKWhmAOQA7AgAAAA==.',
Hu='Hulque:BAAANQADCgYIBgAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQAECgMIAwAAAA==.Hèrifire:BAAANQAECgUICAAAAA==.',
Ic='Icyshadow:BAAANQAECgQIDQAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgcIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUIDAAAAA==.Jangewinde:BAAANQAECgIIAgAAAA==.Jasmind:BAAANQAECgUICgAAAA==.',
Ji='Jiwà:BAABNQAECn8tAAMGAAkKtRMoVQAPAgAGAAkKtRMoVQAPAgAIAAcKnwI2xAAFAQAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAABNQAECn8ZAAIcAAgKrA5FCgDWAQAcAAgKrA5FCgDWAQAAAA==.Kahless:BAAANQADCgcIEQAAAA==.Kaibab:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kalix:BAAANQABCgUICAAAAA==.Kaliyah:BAAANQAECgUIDgAAAA==.Kattrin:BAAANQADCgYICgAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAABNQAECn8VAAQaAAYKUh6ePQDQAQAaAAYK6x2ePQDQAQAbAAEKkCNqrwBpAAAZAAEKAAAa5AAuAAAAAA==.',
Kh='Khazabrew:BAABNQAECn8lAAIOAAgK/h7IBgDYAgAOAAgK/h7IBgDYAgAAAA==.',
Ki='Kiamara:BAAANQAECgUICAAAAA==.Kinderlin:BAABNQAECn8iAAIXAAgKqBIhqQDIAQAXAAgKqBIhqQDIAQAAAA==.Kirbun:BAABNQAECn8nAAIJAAgKwB3UZgCwAgAJAAgKwB3UZgCwAgAAAA==.Kizchaos:BAAANQAECgMIBAAAAA==.',
Ko='Komurash:BAABNQAECn8YAAMBAAgKkBEShQALAgABAAgKkBEShQALAgAeAAIKRgNtOwBVAAAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQABCggIBAAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgQIDQAFAAAAAA==.',
La='Lancaban:BAAANQADCggIHQAAAQ==.',
Le='Lethalarrow:BAAANQAECgcIEAAAAA==.Lethalpally:BAAANQADCggICAAAAA==.Lewismr:BAAANQADCgUIDQABNQAECgcKGwAXAEAVAA==.Lewisr:BAABNQAECn8bAAIXAAcKQBUNngDhAQAXAAcKQBUNngDhAQAAAA==.',
Li='Ligahoo:BAAANQADCggJDwAAAA==.Lilysweets:BAAANQADCgMIAwAAAA==.',
Lo='Lorianne:BAAANQAECgEIAQABNQAECgkJKwAPANIVAA==.Lorryanne:BAABNQAECn8rAAIPAAkK0hV6OgB4AgAPAAkK0hV6OgB4AgAAAA==.',
Lu='Lucianas:BAAANQAECgYICwAAAA==.Lunacat:BAAANQAECgQICQABNQADCgYJDwAFAAAAAA==.Luxdaddy:BAAANQAECgUIBQABNQADCgYJDwAFAAAAAA==.',
Ly='Lysi:BAAANQAECgQIBwAAAA==.',
Ma='Madaea:BAABNQAECn8kAAIVAAgKiRpIEgBUAgAVAAgKiRpIEgBUAgAAAA==.Madameuyen:BAAANQAECgEIAQAAAA==.Madlyn:BAAANQAECgQIBgAAAA==.Magepuppy:BAABNQAECn8cAAMJAAgK+hT1yADxAQAJAAcKTxX1yADxAQATAAEKTxNrPwBEAAAAAA==.Makavali:BAAANQAECgUICgABNQAECgkJSQAXALcTAA==.Makavalii:BAABNQAECn9JAAMXAAkKtxPfdQA9AgAXAAgKVBbfdQA9AgAPAAkKCxNPTwArAgAAAA==.Malanimus:BAAANQAECgQJBwAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgUICwAAAA==.Mandorallen:BAAANQAECgQIBAABNQAECgcIJgAKADAXAA==.Matagi:BAABNQAECn8iAAIQAAgKaBY9VgBtAgAQAAgKaBY9VgBtAgAAAA==.Mate:BAAANQADCgUIBQABNQADCggIGwAFAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECn8lAAIZAAgKRRpwOgA2AgAZAAgKRRpwOgA2AgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgIIAgAAAA==.Melorea:BAAANQAECgIIAQAAAA==.Merdin:BAAANQAECgUIEwAAAA==.Methmartion:BAAANQAECgQICwAAAA==.',
Mi='Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBQAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAABNQAECn8aAAIUAAcKogUmOwATAQAUAAcKogUmOwATAQAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAABNQAECn8cAAICAAcKfxTpegClAQACAAcKfxTpegClAQAAAA==.Moonlilly:BAAANQAECgUICAAAAA==.Mopp:BAAANQAECgQIBgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgYIDAAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECggIHAAPAHcSAA==.',
My='Mylilhunter:BAAANQAECgYICwAAAA==.Myrtheli:BAAANQADCggICAABNQAECggIHQACADATAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECn8qAAIQAAgKWx2dTgCAAgAQAAgKWx2dTgCAAgAAAA==.Nagan:BAAANQAECgYIDAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECn8pAAITAAgKXSXmAQBhAwATAAgKXSXmAQBhAwAAAA==.Nathel:BAAANQAECgQIDQAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nirra:BAAANQAECgIIAgAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAABNQAECn8VAAIZAAcKZwynaABrAQAZAAcKZwynaABrAQAAAA==.Novatron:BAAANQAECgUIDAAAAA==.',
Nu='Nuked:BAAANQAECgUIEQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQAECgMIAwAAAA==.',
Og='Ograskygazer:BAAANQAECgQICwAAAA==.',
Oi='Oieg:BAAANQABCgUIBAAAAA==.',
Om='Omee:BAAANQAECgUICQAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgQICwAAAA==.Orioncheats:BAABNQAECn8pAAMZAAgKHBiyNwBEAgAZAAgKHBiyNwBEAgAbAAEKAACGuwBNAAAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAAANQAECgYIEAAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECggIHQACADATAA==.Pedarias:BAABNQAECn8dAAMCAAgKMBP+ZwDjAQACAAgKMBP+ZwDjAQAfAAEKAABPlAANAAAAAA==.Peon:BAAANQAECgUIDQAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAABNQAECn8aAAIgAAcKPA1jJwBVAQAgAAcKPA1jJwBVAQAAAA==.Phredrick:BAAANQAECgIIAQAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQADCgcIBwAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQAECgcICQAFAAAAAA==.Pokerface:BAAANQAECgQIBAAAAA==.Poongwoon:BAAANQADCgMIAwAAAA==.Pounces:BAAANQAFFAQIBAAAAA==.',
Pr='Precious:BAAANQAECgIIBQABNQAECgcIEAAFAAAAAA==.',
Pu='Puppet:BAAANQAECgcIEAAAAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgcIGQADAB0XAA==.',
Qu='Quattro:BAABNQAECn8bAAIhAAcKyw8zGgCjAQAhAAcKyw8zGgCjAQAAAA==.',
Ra='Racecar:BAAANQAECgUIDQAAAA==.Raezil:BAAANQAECgQICQABNQAECgkJHQASAH8RAA==.Raivyn:BAABNQAECn8mAAIKAAcKMBeDKQDOAQAKAAcKMBeDKQDOAQAAAA==.Rathmora:BAAANQADCggIDgAAAA==.Raylaira:BAAANQADCggIJQABNQAECgIIAgAFAAAAAA==.Raziel:BAAANQADCgYJBgAAAA==.',
Re='Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECn8rAAIEAAkKaiNOAwCSAwAEAAkKaiNOAwCSAwAAAA==.Reposado:BAAANQAECgQIBgAAAA==.Revelare:BAABNQAECn8aAAIGAAcKFBdCZgDWAQAGAAcKFBdCZgDWAQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgQIBwAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQAECggIEwAAAA==.',
Rm='Rmplstiltskn:BAAANQADCgQIBAAAAA==.',
Ro='Robberttrest:BAAANQAECgQIEwAAAA==.Rockyhunter:BAAANQAECgYIBwABNQAECgkJJwAbAGgeAA==.Rockyhunterr:BAABNQAECn8nAAIbAAkKaB6nEQAdAwAbAAkKaB6nEQAdAwAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockyrogue:BAAANQADCggICAABNQAECgkJJwAbAGgeAA==.Rockywarlock:BAAANQAECgEIAQABNQAECgkJJwAbAGgeAA==.Rockywarrior:BAAANQADCgYICgABNQAECgkJJwAbAGgeAA==.Rooth:BAAANQAECgUICQAAAA==.Roryn:BAABNQAECn8xAAIXAAkKFiQ3FQBvAwAXAAkKFiQ3FQBvAwAAAA==.',
Ru='Rubï:BAAANQAECgYICgAAAA==.Rugiaas:BAACNQAFFH8bAAIPAAYK3SKQAgB+AgAPAAYK3SKQAgB+AgA1AAQKfzUAAw8ACQpBJasEAKoDAA8ACQpBJasEAKoDABcABApyFgn2ACsBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAYIGwAPAN0iAA==.',
Ry='Ryuka:BAAANQAECgcIEQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgkJHQASAH8RAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgAFAAAAAA==.Samyria:BAAANQAECgQIBgAAAA==.Satyaru:BAABNQAECn8mAAQOAAgKag+5EQDIAQAOAAgKag+5EQDIAQAVAAQKkgh+OgCYAAAKAAEKAAAqcQAmAAAAAA==.Saucy:BAAANQAECgQIDQAAAA==.',
Se='Sedona:BAAANQAECgUICAAAAA==.Selarra:BAABNQAECn8bAAICAAgKOQ0KewCkAQACAAgKOQ0KewCkAQAAAA==.Seric:BAABNQAECn8fAAMeAAgKWg/DGgCHAQAeAAgKWg/DGgCHAQABAAMK+wHZSAE5AAAAAA==.Sethuriel:BAAANQAECgUIDAAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYJBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Sk='Skoto:BAAANQAECgQIBAAAAA==.',
Sm='Smartfood:BAAANQAECggIBwAAAA==.Smoochybooty:BAAANQAECgMIBAAAAA==.',
So='Solnar:BAABNQAECn8cAAMPAAgKdxIuXwD4AQAPAAgKdxIuXwD4AQAXAAQK8QzaQgGuAAAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFH8MAAIGAAYKwg2ECQCzAQAGAAYKwg2ECQCzAQA1AAQKfzIAAgYACQpCH0QaAAYDAAYACQpCH0QaAAYDAAE1AAMKBgkPAAUAAAAA.Spoiled:BAAANQADCggICAABNQAECgcIEAAFAAAAAA==.',
Sr='Srìracha:BAAANQAECggIAwAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQAECgUICAAAAA==.Stormieskye:BAABNQAECn8kAAIIAAgKvRIqXAAKAgAIAAgKvRIqXAAKAgAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Summonme:BAAANQAECgIIAgAAAA==.Suzume:BAAANQAECgQIBAABNQAFFAcIGgAGAIkYAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQAECgUICwAAAA==.',
Ta='Taea:BAAANQAECgUICgAAAA==.Taeus:BAABNQAECn8nAAQTAAkKkxvKBgCLAgATAAgKXRvKBgCLAgAJAAcKMRem0ADiAQAiAAEKPw9JDAA/AAAAAA==.Taintedkoma:BAAANQAECgMIAwABNQAECgQICwAFAAAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECn8cAAIeAAgKoCKHBgD5AgAeAAgKoCKHBgD5AgAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQAECgIIAgAAAA==.Teratrendera:BAAANQAECgQIDgAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgEIAQAAAA==.',
Th='Thavis:BAABNQAECn8aAAMSAAgKDA7SjwC6AQASAAgKkQvSjwC6AQARAAQKwgwWOwDUAAAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQAECgUICAAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYJBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAABNQAECn8XAAIXAAgKhhX+kAD+AQAXAAgKhhX+kAD+AQAAAA==.Tinkr:BAABNQAECn8fAAIbAAgKLRaqRQDhAQAbAAgKLRaqRQDhAQAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQADCgQIBAAAAA==.Tom:BAAANQAECgUICAABNQAECgkJHQASAH8RAA==.Torrey:BAAANQAECgcIEwAAAA==.Totemsareus:BAABNQAECn8lAAMGAAkKcSPsBwCBAwAGAAkKcSPsBwCBAwAIAAIKigdvEQFjAAAAAA==.Toxx:BAAANQAECgEIAQAAAA==.',
Tr='Tradd:BAACNQAFFH8GAAICAAIKwhwOJACxAAACAAIKwhwOJACxAAA1AAQKfykABAIACQq2INkNAFMDAAIACQq2INkNAFMDACMABwrDDq4MAGsBAB8ABAqICSlOANcAAAAA.Trallor:BAABNQAECn8eAAIBAAcKAw7suwCCAQABAAcKAw7suwCCAQAAAA==.Trhall:BAAANQAECgEIAQAAAA==.Tristyana:BAABNQAECn8lAAIQAAcKEBHxjwDmAQAQAAcKEBHxjwDmAQAAAA==.',
Ts='Tsiddahn:BAABNQAECn8kAAICAAkK9RrtJwDHAgACAAkK9RrtJwDHAgAAAA==.Tsunâde:BAABNQAECn8fAAMKAAgKGSRCCABJAwAKAAgKGSRCCABJAwAVAAQK9w6MMwDJAAAAAA==.',
Ty='Tylurien:BAABNQAECn8aAAIPAAcKSSZ0GQARAwAPAAcKSSZ0GQARAwAAAA==.Tyrael:BAAANQAECgYIEAABNQADCgMIBgAFAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQADCgYICgAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAABNQAECn8bAAIRAAcK3whLIABsAQARAAcK3whLIABsAQAAAA==.',
Va='Valenhi:BAAANQAECgEIAQAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECn8kAAICAAcKGh8POwB6AgACAAcKGh8POwB6AgAAAA==.Valoria:BAAANQAECgEIAQAAAA==.Vanille:BAAANQAECgQIDQAAAA==.Vargen:BAAANQAECgIIBAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECn8mAAIeAAcKUB2IDQBWAgAeAAcKUB2IDQBWAgAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQAECgQIBQAAAA==.Vegasduc:BAAANQADCgQIBAAAAA==.Vegasducks:BAABNQAECn8fAAIJAAcKPgjV/QCOAQAJAAcKPgjV/QCOAQAAAA==.Velara:BAAANQADCgYIDAAAAA==.Veld:BAAANQAECgcICwAAAA==.Velithara:BAAANQADCgYJBgAAAA==.Veralyn:BAAANQADCgQIBAAAAA==.',
Vi='Violet:BAAANQAECgUIDgAAAA==.',
Vy='Vyla:BAAANQABCgcIDAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQADCgQIBAAAAA==.Warfise:BAAANQAECgUICAAAAA==.Warspriest:BAAANQAECgYIEwAAAA==.Warwizard:BAABNQAECn80AAIPAAgKJCbtCACAAwAPAAgKJCbtCACAAwAAAA==.',
Wd='Wdemperor:BAAANQAECgUIEQABNQAECgcIDwAFAAAAAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAFAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQADCgYIGAAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECn8pAAIPAAkKtxk+JwDKAgAPAAkKtxk+JwDKAgAAAA==.',
Wr='Wrathbarrage:BAAANQAECgYICwABNQAECggIIgAgAFwSAA==.Wrathchoi:BAAANQADCgMIAwAAAA==.Wrathstorm:BAABNQAECn8iAAIgAAgKXBICHQCzAQAgAAgKXBICHQCzAQAAAA==.',
Ya='Yazahk:BAAANQADCggJFgABNQADCgYIBAAFAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggIDwAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFH8aAAIbAAcK+iCpAQCdAgAbAAcK+iCpAQCdAgA1AAQKfx8AAxsACQp5IrQVAP0CABsACQp5IrQVAP0CABoAAQrdHKuaAFUAAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQADCgYIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgUICwAAAA==.Zeva:BAAANQAECgQICAAAAA==.',
Zo='Zonzmik:BAAANQABCgYIBAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQAECgIIAgAFAAAAAA==.',
Zu='Zurazaee:BAAANQAECgQIDgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECn8lAAIgAAcKLwprLgAhAQAgAAcKLwprLgAhAQAAAA==.',
['Ïr']='Ïridescent:BAAANQAECgIIAgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
