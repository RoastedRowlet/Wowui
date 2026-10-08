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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Druid-Balance','Shaman-Elemental','Mage-Arcane','Monk-Windwalker','DemonHunter-Vengeance','Druid-Feral','Monk-Brewmaster','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Monk-Mistweaver','Paladin-Retribution','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Mage-Frost','DeathKnight-Blood','Priest-Shadow','Evoker-Devastation','Warrior-Protection','Priest-Discipline','Druid-Guardian',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAAANQAECgUIDgAAAA==.',
Ad='Ado:BAAANQAECgUICAAAAA==.Adversity:BAAANQAFFAMIBAAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.Aevintz:BAAANQAECgYIBgAAAA==.',
Ai='Aiolii:BAAANQAECgQICgAAAA==.',
Ak='Akiras:BAAANQABCgQICAAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Aldea:BAAANQAECgUIBQABNQAECggIGgABAGwRAA==.Alyndrya:BAABNQAECoEiAAICAAgKLQ4GKADkAQACAAgKLQ4GKADkAQAAAA==.',
Am='Amithralia:BAABNQAECoEZAAIDAAcK0iA+EwCTAgADAAcK0iA+EwCTAgAAAA==.',
An='Anejo:BAAANQAECgQIBAAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQADCgcIFgABNQAECgIIAgAEAAAAAA==.Anzarna:BAAANQADCggIIQABNQADCggIJQAEAAAAAA==.',
Ao='Aohikari:BAAANQAECgMIBAABNQAFFAcIGQAFAHAYAA==.',
Ap='Aprigity:BAAANQAECgIJAwAAAA==.',
Aq='Aquaten:BAAANQAECgQICgAAAA==.',
Ar='Arashinigon:BAABNQAECoEVAAMDAAYKwhRYOAAlAQADAAUKqBFYOAAlAQAGAAEK+w3MmwA+AAAAAA==.Arceus:BAAANQAECgIJAgAAAA==.Arick:BAAANQAECgYIEQAAAA==.Ark:BAABNQAECoE2AAMFAAkK+yYIAAAGBAAFAAkK+yYIAAAGBAAHAAEKHCQW+gBeAAAAAA==.',
As='Astrofax:BAAANQABCggIDQAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAAANQAECgYICAAAAA==.',
Ax='Axon:BAABNQAECoEZAAIIAAcKtwaIAAFmAQAIAAcKtwaIAAFmAQAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAAANQAECgQICgAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAABNQAECoEhAAMFAAgKbxg0OQBSAgAFAAgKbxg0OQBSAgAHAAEK7AHLNQEgAAAAAA==.Battlebot:BAAANQAECgQIBwAAAA==.',
Be='Beet:BAABNQAECoEYAAIJAAcKeSI8EgCqAgAJAAcKeSI8EgCqAgAAAA==.Belgaron:BAAANQAECgQIBAABNQAECgcIHwAJAOwWAA==.Belitha:BAABNQAECoEcAAICAAgKViGjDwDlAgACAAgKViGjDwDlAgAAAA==.Belmaris:BAAANQAECgYIEAAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgQIBQAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECgQIBAAEAAAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgQIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAABNQAECoEaAAIKAAcKRh6zBwBZAgAKAAcKRh6zBwBZAgAAAA==.Bloomharvest:BAAANQADCgEIAQAAAA==.Bluegrass:BAABNQAECoEfAAILAAgKkhyiCACVAgALAAgKkhyiCACVAgAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAABNQAECoEYAAIMAAYKPSCeCwAxAgAMAAYKPSCeCwAxAgAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAcIFwABAF4dAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgEIAQAAAA==.Brisket:BAAANQADCggIGwAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAAANQAECgcIEAAAAA==.Bubbs:BAAANQADCgQIBAABNQAECggIFwAJAOsgAA==.Buckme:BAABNQAECoEhAAINAAkK7hrKJADmAgANAAkK7hrKJADmAgAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAcIEwAOAL8iAA==.Busen:BAAANQADCggIFgAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECoEbAAMPAAgKuRLrbQDtAQAPAAgKuRLrbQDtAQAOAAEKNxHKbAA9AAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQAECgQIBgAAAA==.Caralhan:BAAANQAECgQICAAAAA==.Castelo:BAAANQADCggICAAAAA==.',
Ce='Cedra:BAABNQAECoE0AAIIAAkK8CJxFAB7AwAIAAkK8CJxFAB7AwAAAA==.Cegeo:BAABNQAECoEaAAIOAAcK/RQUEADzAQAOAAcK/RQUEADzAQAAAA==.Celari:BAAANQAECgEIAQAAAA==.',
Ch='Cheepdeeps:BAABNQAECoEeAAIQAAcKGxhDggDyAQAQAAcKGxhDggDyAQAAAA==.Chelea:BAAANQABCggIGQAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgMIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQAECgQICAAAAA==.Cirdle:BAAANQAECgYIEwAAAA==.',
Co='Cobalt:BAECNQAFFIEEAAIPAAIKUBPUJQChAAAPAAIKUBPUJQChAAA1AAQKgSEAAg8ACQppHgMcAP8CAA8ACQppHgMcAP8CAAAA.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAABNQAECoEUAAIHAAYKEAO3xADbAAAHAAYKEAO3xADbAAAAAA==.Crucifixea:BAAANQAECgcIEwAAAA==.Cruxsader:BAAANQADCgcICgAAAA==.Crystyl:BAAANQAECgQICAAAAA==.',
Ct='Ctesias:BAAANQADCgYIBgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAQIBAAEAAAAAA==.Cute:BAAANQAECgYIBgABNQAFFAcIFwABAF4dAA==.',
Cy='Cymoril:BAABNQAECoEfAAIQAAgKCxYTcwAaAgAQAAgKCxYTcwAaAgAAAA==.',
Da='Daamass:BAAANQADCgMIAwAAAA==.Daddy:BAABNQAECoFIAAIRAAkK5yYOAAAIBAARAAkK5yYOAAAIBAAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAAANQAECgYICgAAAA==.Darkcarnival:BAAANQAECgYIDwAAAA==.Darkkill:BAAANQADCgMIAwABNQAECgkJIQAFALoiAA==.Dasnotgood:BAAANQADCggIHgAAAA==.',
De='Deemon:BAAANQAECgUIDgAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Denard:BAAANQADCgUICQABNQADCggIGwAEAAAAAA==.Denarias:BAAANQADCgUJBQABNQADCggIJQAEAAAAAA==.Denevien:BAAANQAECgQIBgAAAA==.Desdemona:BAAANQAECgQICAAAAA==.Dethiaris:BAAANQAECgQIBgAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAAANQAECgcIDgAAAA==.',
Do='Dobutsu:BAAANQAECgcICwAAAA==.Doomace:BAABNQAECoEkAAISAAgKXRJghADtAQASAAgKXRJghADtAQAAAA==.',
Dr='Draaka:BAAANQADCgYIDAAAAA==.Dragee:BAAANQAECgQIBAABNQAECgUIDgAEAAAAAA==.Dragon:BAAANQAECgcIBwAAAA==.Driftyshaman:BAAANQADCggIHgAAAA==.Droopy:BAAANQADCgUICgAAAA==.Dræghoule:BAAANQAECgQIBwAAAA==.',
Du='Durnik:BAAANQAECgYIDwABNQAECgcIHwAJAOwWAA==.',
Dw='Dworflundgrn:BAAANQAECgYICgAAAA==.',
Dy='Dyamí:BAAANQAECgYIEAAAAA==.',
['Dá']='Dánte:BAAANQAECgIIAgAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECoEmAAMDAAgKJwcTLgB1AQADAAgKJwcTLgB1AQAGAAUKiRfhVQBVAQAAAA==.Eldiablo:BAAANQAECgMIBQAAAA==.Electric:BAAANQAECgQICQAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECoEdAAIIAAcKzAYm/QBtAQAIAAcKzAYm/QBtAQAAAA==.Elrythe:BAABNQAECoEqAAINAAkKlBwCIwDuAgANAAkKlBwCIwDuAgAAAA==.',
Er='Eraleth:BAAANQAECgUIBgABNQAECggIHAACAFYhAA==.',
Fa='Faced:BAAANQAECgUICwAAAA==.Fatalii:BAAANQAECgUIBQAAAA==.',
Fe='Felebash:BAAANQAECgUIBgAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECoEkAAITAAkKrCTiAQCWAwATAAkKrCTiAQCWAwAAAA==.Floofthulu:BAAANQADCggICAAAAA==.Fluffalo:BAABNQAECoEbAAIHAAgKRSDSHgD3AgAHAAgKRSDSHgD3AgABNQAECgkJJAATAKwkAA==.',
Fo='Foxypocket:BAAANQAECgQICgAAAA==.',
Fr='Fredrickk:BAAANQAECgQIBwAAAA==.',
Fu='Furcas:BAAANQADCgMIAwAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgkJJAATAKwkAA==.Furrylight:BAAANQAECgEIAQABNQAECgkJGwAFAF8fAA==.Furryphase:BAABNQAECoEbAAMFAAkKXx8HGwDnAgAFAAkKXx8HGwDnAgAHAAEKeAJwNAEhAAAAAA==.Fuzzington:BAAANQAECgUIBQABNQAECgkJJAATAKwkAA==.',
Ga='Galnier:BAAANQAECgIJBQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaur:BAAANQAECgcIEgAAAA==.',
Gr='Gripisrdy:BAAANQAECgYIDwAAAA==.',
Gu='Gunslingr:BAABNQAECoEgAAIUAAgKUyLHAgAMAwAUAAgKUyLHAgAMAwAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAAANQAECggIDwAAAA==.',
He='Headpats:BAAANQAFFAIIAgABNQAFFAQIBAAEAAAAAA==.Hearthisrdy:BAAANQADCggIDwAAAA==.Hexwhisper:BAAANQAECgMIAwAAAA==.Heycarlos:BAABNQAECoEqAAMVAAkKpyAJCgA3AwAVAAkKpyAJCgA3AwAWAAIKTAfxuwBRAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAcIGQAFAHAYAA==.Hikarishaman:BAACNQAFFIEZAAMFAAcKcBgtCACvAQAFAAUK6hUtCACvAQAHAAQKRRUtDgBLAQA1AAQKgSUAAwcACQrJG/1AAEcCAAcACAppGv1AAEcCAAUACQqiG0VCAC0CAAAA.Hime:BAAANQAECgYIDAAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAAANQAECgcIEQAAAA==.',
Hu='Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQADCggIFAAAAA==.Hèrifire:BAAANQAECgUIBwAAAA==.',
Ic='Icyshadow:BAAANQAECgQICQAAAA==.',
Id='Idouna:BAAANQADCgEIAQAAAA==.',
Ih='Ihalo:BAAANQAECgYIEAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUICAAAAA==.Jangewinde:BAAANQADCgQIBAAAAA==.Jasmind:BAAANQAECgQIBQAAAA==.',
Ji='Jiwà:BAABNQAECoEqAAMFAAkKnhMZSgAOAgAFAAkKnhMZSgAOAgAHAAcKxQI7rwAGAQAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAAANQAECgcIEAAAAA==.Kahless:BAAANQADCgcIEQAAAA==.Kaibab:BAAANQABCggIEQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kaliyah:BAAANQAECgUIDgAAAA==.Kattrin:BAAANQADCgQIBAAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAAANQAECgYIEwAAAA==.',
Kh='Khazabrew:BAABNQAECoEdAAIMAAgKMx9bBgDLAgAMAAgKMx9bBgDLAgAAAA==.',
Ki='Kiamara:BAAANQAECgQICAAAAA==.Kinderlin:BAABNQAECoEcAAISAAgKRRACtAB+AQASAAgKRRACtAB+AQAAAA==.Kirbun:BAABNQAECoEgAAIIAAgKkhtDfwBoAgAIAAgKkhtDfwBoAgAAAA==.Kizchaos:BAAANQAECgMIAwAAAA==.',
Ko='Komurash:BAAANQAECgYIDQAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Kr='Kravvelocity:BAAANQABCggIBAAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgQICQAEAAAAAA==.',
La='Lancaban:BAAANQADCggIHQAAAQ==.',
Le='Lethalarrow:BAAANQAECgcICgAAAA==.Lethalpally:BAAANQADCggICAAAAA==.Lewismr:BAAANQADCgUICgABNQADCggIJQAEAAAAAA==.Lewisr:BAAANQAECgYIEgAAAA==.',
Li='Ligahoo:BAAANQADCggJDwAAAA==.Lilysweets:BAAANQADCgMIAwAAAA==.',
Lo='Lorianne:BAAANQAECgEIAQABNQAECggIIwAXAKAPAA==.Lorryanne:BAABNQAECoEjAAIXAAgKoA9zWQDqAQAXAAgKoA9zWQDqAQAAAA==.',
Lu='Lucianas:BAAANQAECgYIBgAAAA==.Lunacat:BAAANQAECgQIBQABNQADCgYJDwAEAAAAAA==.',
Ly='Lysi:BAAANQAECgMIAwAAAA==.',
Ma='Madaea:BAABNQAECoEiAAIRAAgKfhp6DwBhAgARAAgKfhp6DwBhAgAAAA==.Madameuyen:BAAANQAECgEIAQAAAA==.Madlyn:BAAANQAECgQIBAAAAA==.Magepuppy:BAABNQAECoEcAAMIAAgK5xYhrwACAgAIAAcKahchrwACAgAYAAEKTxP9OABEAAAAAA==.Makavali:BAAANQADCgYIBgABNQAECggIQwASAAoYAA==.Makavalii:BAABNQAECoFDAAMSAAgKChgyXABZAgASAAgKChgyXABZAgAXAAgKURMnVQD5AQAAAA==.Malanimus:BAAANQAECgQJBwAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgUIBwAAAA==.Matagi:BAABNQAECoEbAAINAAgKsxbOSwBjAgANAAgKsxbOSwBjAgAAAA==.Mate:BAAANQADCgUIBQABNQADCggIGwAEAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECoEfAAIWAAgK/Rh9OQAZAgAWAAgK/Rh9OQAZAgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgIIAgAAAA==.Melorea:BAAANQAECgEIAQAAAA==.Merdin:BAAANQAECgUIEwAAAA==.Methmartion:BAAANQAECgQICgAAAA==.',
Mi='Milougheh:BAAANQAECggIAgAAAA==.Minós:BAAANQADCgUIBQAAAA==.Mish:BAAANQAECgQIBAAAAA==.Missiah:BAAANQAECgYIEQAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIJAgAAAA==.Moonfell:BAABNQAECoEXAAIBAAcKfxR8agCpAQABAAcKfxR8agCpAQAAAA==.Moonlilly:BAAANQAECgQICAAAAA==.Mopp:BAAANQAECgIIAgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgQIBwAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECgcIGQAXAMkQAA==.',
My='Mylilhunter:BAAANQAECgYICwAAAA==.Myrtheli:BAAANQADCggICAABNQAECggIGgABAGwRAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECoEjAAINAAgKwxqfQACEAgANAAgKwxqfQACEAgAAAA==.Nagan:BAAANQAECgYICwAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECoEhAAIYAAgKlCWyAQBWAwAYAAgKlCWyAQBWAwAAAA==.Nathel:BAAANQAECgQICQAAAA==.',
Ne='Nerisa:BAAANQADCgUIBQAAAA==.',
Ni='Nirra:BAAANQADCgYJBgAAAA==.',
No='Noctis:BAAANQAECgYICwAAAA==.Notoriginal:BAAANQAECgcIDgAAAA==.Novatron:BAAANQAECgUICAAAAA==.',
Nu='Nuked:BAAANQAECgUIEQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQADCgQIBAAAAA==.',
Og='Ograskygazer:BAAANQAECgQIBwAAAA==.',
Oi='Oieg:BAAANQABCgUIBAAAAA==.',
Om='Omee:BAAANQAECgQICQAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgQICgAAAA==.Orioncheats:BAABNQAECoEhAAMWAAgKEhZcSADPAQAWAAgKaxVcSADPAQAZAAEK6hsQrgBPAAAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAAANQAECgUICgAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECggIGgABAGwRAA==.Pedarias:BAABNQAECoEaAAMBAAgKbBE7XADdAQABAAgKbBE7XADdAQAaAAEKtgBthQAOAAAAAA==.Peon:BAAANQAECgUICQAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAAANQAECgYIDwAAAA==.Phredrick:BAAANQAECgEIAQAAAA==.',
Pi='Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQADCgcIBwAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQAECgUIBQAEAAAAAA==.Pokerface:BAAANQAECgQIBAAAAA==.Pounces:BAAANQAFFAQIBAAAAA==.',
Pr='Precious:BAAANQAECgIIBQABNQAFFAcIFwABAF4dAA==.',
Pu='Puppet:BAAANQAECgcIEAABNQAFFAcIFwABAF4dAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgUIDgAEAAAAAA==.',
Qu='Quattro:BAABNQAECoEUAAIbAAcKWw15GQCSAQAbAAcKWw15GQCSAQAAAA==.',
Ra='Racecar:BAAANQAECgUICAAAAA==.Raezil:BAAANQAECgQICQABNQAECggIGwAPALkSAA==.Raivyn:BAABNQAECoEfAAIJAAcK7BYFJADYAQAJAAcK7BYFJADYAQAAAA==.Rathmora:BAAANQADCggICAAAAA==.Raylaira:BAAANQADCggIJQAAAA==.Raziel:BAAANQADCgYJBgAAAA==.',
Re='Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECoEiAAIDAAgKwiIMCQAcAwADAAgKwiIMCQAcAwAAAA==.Reposado:BAAANQAECgQIBgAAAA==.Revelare:BAAANQAECgYIDwAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgQIBQAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQAECgYICQAAAA==.',
Ro='Robberttrest:BAAANQAECgQIDgAAAA==.Rockyhunterr:BAABNQAECoEhAAIZAAgK0R+PGgDCAgAZAAgK0R+PGgDCAgAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockywarlock:BAAANQAECgEIAQAAAA==.Rockywarrior:BAAANQADCgYICgABNQAECggIIQAZANEfAA==.Rooth:BAAANQAECgQIBQAAAA==.Roryn:BAABNQAECoEoAAISAAkKxiKlFABiAwASAAkKxiKlFABiAwAAAA==.',
Ru='Rubï:BAAANQAECgYICgAAAA==.Rugiaas:BAACNQAFFIEVAAIXAAYKiiIRAgB1AgAXAAYKiiIRAgB1AgA1AAQKgTIAAxcACQpBJU4DALUDABcACQpBJU4DALUDABIABAo2GWLWADQBAAAA.Rugian:BAAANQAECgQIBQABNQAFFAYIFQAXAIoiAA==.',
Ry='Ryuka:BAAANQAECgYIEAAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECggIGwAPALkSAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgAEAAAAAA==.Samyria:BAAANQAECgIIAwAAAA==.Satyaru:BAABNQAECoEeAAQMAAgKZwwfEwCSAQAMAAgKZwwfEwCSAQARAAQKkgheNQCZAAAJAAEKAQZ3ZQAmAAAAAA==.Saucy:BAAANQAECgQICQAAAA==.',
Se='Sedona:BAAANQAECgQICAAAAA==.Selarra:BAABNQAECoEbAAIBAAgKOQ2CaQCsAQABAAgKOQ2CaQCsAQAAAA==.Seric:BAABNQAECoEeAAMcAAcK1Q9oGgBjAQAcAAcK1Q9oGgBjAQAQAAMK+wEwLwE6AAAAAA==.Sethuriel:BAAANQAECgUIDAAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYJBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Sk='Skoto:BAAANQAECgQIBAAAAA==.',
Sm='Smartfood:BAAANQAECggIAwAAAA==.Smoochybooty:BAAANQAECgEIAQAAAA==.',
So='Solnar:BAABNQAECoEZAAMXAAcKyRASawCvAQAXAAcKyRASawCvAQASAAQK7wowHwGyAAAAAA==.',
Sp='Specter:BAAANQAECggICAAAAA==.Splashdaddy:BAACNQAFFIEMAAIFAAYKwg3xBgDNAQAFAAYKwg3xBgDNAQA1AAQKgSwAAgUACQpCH8wUAA0DAAUACQpCH8wUAA0DAAE1AAMKBgkPAAQAAAAA.Spoiled:BAAANQADCggICAABNQAFFAcIFwABAF4dAA==.',
Sr='Srìracha:BAAANQAECggIAwAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQAECgQICAAAAA==.Stormieskye:BAABNQAECoEcAAIHAAgKJRN0UgACAgAHAAgKJRN0UgACAgAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Suzume:BAAANQAECgQIBAABNQAFFAcIGQAFAHAYAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQAECgUIBwAAAA==.',
Ta='Taea:BAAANQAECgUIBgAAAA==.Taeus:BAABNQAECoEfAAMYAAgKTRhYGAAQAQAIAAcKiBZvswD6AQAYAAMKECBYGAAQAQAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECoEcAAIcAAgKhSIUBQALAwAcAAgKhSIUBQALAwAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQADCgUJBQABNQADCggIJQAEAAAAAA==.Teratrendera:BAAANQAECgQICgAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgEIAQAAAA==.',
Th='Thavis:BAAANQAECggIEgAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQAECgQICAAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYJBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAAANQAECggIEAAAAA==.Tinkr:BAABNQAECoEYAAIZAAgKDBLBQgDSAQAZAAgKDBLBQgDSAQAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQADCgQIBAAAAA==.Tom:BAAANQAECgUICAABNQAECggIGwAPALkSAA==.Torrey:BAAANQAECgYIDAAAAA==.Totemsareus:BAABNQAECoEhAAMFAAkKuiIYCABwAwAFAAkKuiIYCABwAwAHAAIKigf39ABnAAAAAA==.Toxx:BAAANQAECgEIAQAAAA==.',
Tr='Tradd:BAABNQAECoEmAAQBAAkK7R0DHADqAgABAAgKnR8DHADqAgAdAAcKww73CgB/AQAaAAQKCg2jRgDcAAAAAA==.Trallor:BAAANQAECgYIEgAAAA==.Trhall:BAAANQAECgEIAQAAAA==.Tristyana:BAABNQAECoEeAAINAAcKBwwljgC8AQANAAcKBwwljgC8AQAAAA==.',
Ts='Tsiddahn:BAABNQAECoEfAAIBAAkKoRpTIQDNAgABAAkKoRpTIQDNAgAAAA==.Tsunâde:BAABNQAECoEXAAMJAAgK6yDGDgDZAgAJAAgK6yDGDgDZAgARAAQK9w5ALgDPAAAAAA==.',
Ty='Tylurien:BAAANQAECgYIDwAAAA==.Tyrael:BAAANQAECgUICgABNQADCgMIBgAEAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQADCgYICgAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAABNQAECoEXAAIOAAcKfAmrIABhAQAOAAcKfAmrIABhAQAAAA==.',
Va='Valenhi:BAAANQADCgQICgAAAA==.Valkoinen:BAAANQADCgMIBgAAAA==.Valora:BAABNQAECoEdAAIBAAcKtB3eMgB7AgABAAcKtB3eMgB7AgAAAA==.Valoria:BAAANQAECgEIAQAAAA==.Vanille:BAAANQAECgQICQAAAA==.Vargen:BAAANQAECgIIBAAAAA==.Varonika:BAAANQAECgUIBwAAAA==.Vayla:BAABNQAECoEfAAIcAAcKyR19CwBYAgAcAAcKyR19CwBYAgAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQAECgEIAQAAAA==.Vegasducks:BAABNQAECoEWAAIIAAcKJQbmBAFfAQAIAAcKJQbmBAFfAQAAAA==.Velara:BAAANQADCgYIDAAAAA==.Veld:BAAANQAECgcIBgAAAA==.Velithara:BAAANQADCgYJBgAAAA==.',
Vi='Violet:BAAANQAECgQICQAAAA==.',
Vy='Vyla:BAAANQABCgcIDAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQADCgQIBAAAAA==.Warfise:BAAANQAECgUIBwAAAA==.Warspriest:BAAANQAECgYIDgAAAA==.Warwizard:BAABNQAECoEsAAIXAAgKAyaxBwCBAwAXAAgKAyaxBwCBAwAAAA==.',
Wd='Wdemperor:BAAANQAECgUIDAABNQAECgcIDgAEAAAAAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEJAQABNQAECgEIAQAEAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQADCgUIEgAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECoEgAAIXAAgKERnaNQBxAgAXAAgKERnaNQBxAgAAAA==.',
Wr='Wrathbarrage:BAAANQAECgUIBQABNQAECggIGwAeAEgLAA==.Wrathchoi:BAAANQADCgIIAQAAAA==.Wrathstorm:BAABNQAECoEbAAIeAAgKSAvaHgBiAQAeAAgKSAvaHgBiAQAAAA==.',
Ya='Yazahk:BAAANQADCggJFgABNQADCgYIBAAEAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggICwAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFIEZAAIZAAcKRiDlAAC2AgAZAAcKRiDlAAC2AgA1AAQKgR4AAhkACQoGIh8RABADABkACQoGIh8RABADAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQADCgYIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgUICwAAAA==.Zeva:BAAANQAECgQIBgAAAA==.',
Zo='Zonzmik:BAAANQABCgYIBAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgQIBAABNQADCggIJQAEAAAAAA==.',
Zu='Zurazaee:BAAANQAECgQICgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECoEeAAIeAAcKuAgMJgAfAQAeAAcKuAgMJgAfAQAAAA==.',
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
