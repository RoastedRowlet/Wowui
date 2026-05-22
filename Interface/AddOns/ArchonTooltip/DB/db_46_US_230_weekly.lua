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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Elemental','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','Monk-Windwalker','DeathKnight-Blood','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abaddon:BAABLgAECn8jAAMBAAgJ+x2+BwCuAQABAAYJxiC+BwCuAQACAAcJbRuITwCcAQAAAA==.',
Ac='Acidtears:BAAALgADCgcJDQAAAA==.Ackris:BAABLgAECn8uAAIDAAkJ/BwHCgAuAwADAAkJ/BwHCgAuAwAAAA==.Ackrisa:BAAALgAECgUJBQAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJLgADAPwcAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgIJAwABLgAECggJIwAFAIIPAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMGAAgJDRXWQACGAQAGAAgJDRXWQACGAQAHAAEJawwvTgAzAAABLgAFFAYJFwAIADITAA==.Amalthaea:BAAALgAECgUJBQABLgAECgkJJwAJAMEVAA==.Amnoon:BAABLgAECn8nAAIKAAkJjxevDgBrAgAKAAkJjxevDgBrAgAAAA==.Amri:BAACLgAFFH8QAAILAAQJCw49HwAaAQALAAQJCw49HwAaAQAuAAQKfxsAAwsACAlxFqAVAC0CAAsACAlxFqAVAC0CAAwAAwkMBco8AIQAAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgIJAQAAAA==.',
Aq='Aquas:BAAALgAECgQJBwAAAA==.',
Ar='Ardrhys:BAAALgAECgYJDQAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECggJCQABLgAFFAUJEAAHAOUVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgQJCAAAAA==.',
At='Atreus:BAABLgAECn8jAAIHAAkJ8xrTCQA5AgAHAAkJ8xrTCQA5AgAAAA==.Atzalan:BAABLgAECn8UAAINAAYJpwnpcwD7AAANAAYJpwnpcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8rAAMOAAkJZw+QFABlAQAOAAkJZw+QFABlAQAPAAEJ+wnERAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8rAAINAAgJShmgKgDGAQANAAgJShmgKgDGAQAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Bearooter:BAAALgADCgUJCAABLgAFFAUJEAAMALEkAA==.Beastcloud:BAAALgAECgIJAgABLgAECgkJIwAHAPMaAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8bAAICAAgJ/BTZRAC8AQACAAgJ/BTZRAC8AQAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIQAAcJZSB1SAAJAgAQAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMQAAIJOQzYaACDAAAQAAIJUAXYaACDAAARAAIJOQwOCAA2AAAuAAQKfywAAxEACQnYIzsBABIDABEACQnYIzsBABIDABAAAQmPFbUWAU8AAAAA.Bonedmuch:BAAALgADCgUJCgABLgAECgkJJwAJAMEVAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8VAAISAAYJJwarDwC/AAASAAYJJwarDwC/AAAAAA==.Breadria:BAAALgADCgMJAwABLgAFFAMJBwATAH0FAA==.Bremitin:BAAALgADCggJCAABLgAECggJLQARAFYQAA==.Bremitus:BAAALgADCgkJCQABLgAECggJLQARAFYQAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8YAAIGAAcJhx+wNwAXAgAGAAcJhx+wNwAXAgAAAA==.Brud:BAAALgAECgMJCQAAAA==.Brunstan:BAACLgAFFH8NAAIUAAQJvh6qCQBTAQAUAAQJvh6qCQBTAQAuAAQKfxcAAhQACQnSHs0CAIACABQACQnSHs0CAIACAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8XAAMIAAYJMhN1BQCDAQAIAAUJaxN1BQCDAQAFAAEJaA9OTQBSAAAuAAQKfyAABAgACQktH5oPAK8CAAgACQktH5oPAK8CABUAAQm+F78pAEEAAAUAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8fAAIWAAcJMQgulAAfAQAWAAcJMQgulAAfAQAAAA==.',
Ca='Cain:BAAALgADCgMJCAAAAA==.Calvisi:BAAALgAECgUJCgAAAA==.Calvisichaos:BAABLgAECn8mAAIXAAkJBRNBBQDPAQAXAAkJBRNBBQDPAQAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgMJAwAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgQJBgAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAIJAQAAAA==.Cropala:BAABLgAECn8fAAIQAAkJUxLhNADxAQAQAAkJUxLhNADxAQAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgIJAgAAAA==.Darkwingduck:BAAALgADCgEJAQAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJBwAAAA==.',
De='Deleto:BAABLgAECn8cAAMBAAgJWBTWCgBiAQABAAcJXRDWCgBiAQACAAYJYBg4bwBMAQAAAA==.Dellandre:BAAALgAECgUJDQABLgAECgkJJwARAOkIAA==.Delta:BAABLgAECn8SAAIGAAgJHAcOpwCJAAAGAAgJHAcOpwCJAAAAAA==.Delti:BAAALgAECgUJBgABLgAECggJHAAGAMUWAA==.Demondozer:BAAALgAECgMJAwABLgAECgUJCQAEAAAAAA==.Demony:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAABLgAECn8VAAIDAAkJNQfeVwBlAQADAAkJNQfeVwBlAQAAAA==.Digichowder:BAACLgAFFH8FAAIYAAMJ1BUmHgD4AAAYAAMJ1BUmHgD4AAAuAAQKfxsAAw8ABwlFGzEQAKMBAA8ABgneGDEQAKMBABgABQkXGAA7ABgBAAAA.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJBgAAAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn8vAAMXAAgJMyGPAgBIAgAXAAcJIyOPAgBIAgADAAQJIBQLiwD1AAAAAA==.Eldhe:BAAALgAECgQJBQAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAABLgAECn8WAAMUAAgJjRU0MwCgAQAUAAcJABc0MwCgAQAZAAQJVw6xLQD1AAAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8WAAIMAAgJzRPHCwDcAQAMAAgJzRPHCwDcAQAAAA==.Endlol:BAABLgAECn8pAAMaAAgJSyF0CgBpAgAaAAgJSyF0CgBpAgAbAAEJWB97UABWAAABLgAFFAIJAwAEAAAAAA==.',
Er='Eredaria:BAAALgAECgUJCQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8SAAIWAAYJjBRNDwCeAQAWAAYJjBRNDwCeAQAuAAQKfyQAAhYACQk+IBsjAOYCABYACQk+IBsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RoNTgCgAQACAAcJ7RoNTgCgAQAAAA==.',
Es='Esv:BAAALgAECgQJBwABLgAFFAQJDwAWAEgNAA==.',
Ex='Excido:BAAALgAECgEJAQAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgIJAwAAAA==.Fadedheart:BAAALgAECgQJBwABLgAECggJLgACACIhAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAABLgAECn8uAAICAAgJIiFLGgBwAgACAAgJIiFLGgBwAgAAAA==.Faeyir:BAACLgAFFH8IAAIWAAQJ8QuiRAAzAQAWAAQJ8QuiRAAzAQAuAAQKfyAAAhYACQmmGz9QAEYCABYACQmmGz9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMTAAkJqCC0BgD6AgATAAkJqCC0BgD6AgAUAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIWAAMJwBhaVwD6AAAWAAMJwBhaVwD6AAAuAAQKfysAAhYACQmUISERAMUCABYACQmUISERAMUCAAAA.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgEJAgABLgAECgMJAwAEAAAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.Frostydh:BAAALgAECgMJAwAAAA==.Frostytotems:BAAALgAECgEJAgAAAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gi='Gilberticus:BAAALgAECgQJCgABLgAECgkJOAAcAJUgAA==.Gishmou:BAABLgAECn8cAAIFAAgJKhv9HgAMAgAFAAgJKhv9HgAMAgAAAA==.',
Go='Goldblade:BAABLgAECn8eAAIQAAgJPRazQwC+AQAQAAgJPRazQwC+AQAAAA==.',
Gr='Greyoll:BAAALgAECgYJCAAAAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8aAAIdAAYJHiXbAAAmAgAdAAYJHiXbAAAmAgAuAAQKfxsAAh0ACQmsJb0BAGcDAB0ACQmsJb0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAECggJDQABLgAFFAYJGgAdAB4lAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgQJBAAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Hollowheart:BAABLgAECn8nAAIFAAkJIBjmFwBCAgAFAAkJIBjmFwBCAgAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hy='Hylanna:BAAALgAECgYJCgAAAA==.Hyorinmaru:BAAALgAECgIJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECggJLQARAFYQAA==.',
Ic='Ici:BAABLgAECn8nAAIQAAgJ8gZqiQAhAQAQAAgJ8gZqiQAhAQAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAIJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBAAAAA==.',
In='Intensifies:BAAALgAECgcJDgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAAALgAECgUJBQABLgAECgkJIwAeAJ4LAA==.Iskothar:BAABLgAECn8hAAIRAAgJEx1CBgA/AgARAAgJEx1CBgA/AgAAAA==.',
Iv='Ivarboneless:BAAALgAECgQJDAAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAIJAQAAAA==.',
Je='Jefftrep:BAAALgAECgIJAgAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAAALgAECggJCQAAAA==.',
Ke='Ketesh:BAABLgAECn8uAAIfAAgJax/3BQBWAgAfAAgJax/3BQBWAgABLgAFFAQJEAALAAsOAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgADCgkJEAABLgAECggJIQARABMdAA==.',
Kl='Kleanse:BAAALgAFFAIJAQAAAA==.',
Kn='Knastey:BAABLgAECn8UAAQeAAYJ4BekJwBFAQAeAAYJ4BekJwBFAQANAAYJZAqbcQABAQAgAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAAALgAECgYJEAAAAA==.',
Kr='Krej:BAAALgAECgkJEwABLgAFFAUJEAAHAOUVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgIJAwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDAAAAA==.',
La='Langarde:BAABLgAECn8WAAIOAAgJsQy1GQApAQAOAAgJsQy1GQApAQAAAA==.Laoghaire:BAABLgAECn8YAAIHAAcJ+ANMLwC2AAAHAAcJ+ANMLwC2AAAAAA==.',
Le='Leonz:BAACLgAFFH8UAAIYAAYJKh9+AwC4AQAYAAYJKh9+AwC4AQAuAAQKfywAAhgACQnKIpwCAB4DABgACQnKIpwCAB4DAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAEBLgAECn8kAAICAAgJdBuwQgDDAQACAAgJdBuwQgDDAQAAAA==.',
Li='Liraffemynn:BAACLgAFFH8HAAIhAAMJxRypGwDvAAAhAAMJxRypGwDvAAAuAAQKfzQAAiEACQk2I1ACAHUDACEACQk2I1ACAHUDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Luckylucy:BAABLgAECn8UAAIbAAYJuRX4JABfAQAbAAYJuRX4JABfAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8VAAICAAYJxxVwggB+AQACAAYJxxVwggB+AQAAAA==.Magus:BAAALgADCgkJEQABLgAECgMJBwAEAAAAAA==.Maldran:BAABLgAECn8XAAIFAAcJjh3yHAAbAgAFAAcJjh3yHAAbAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAAALgAECgYJEQAAAA==.Marien:BAABLgAECn8WAAIdAAgJ8xfvEwCJAQAdAAgJ8xfvEwCJAQAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8FAAIWAAIJKSSQZgDSAAAWAAIJKSSQZgDSAAAuAAQKfyYAAhYACQmmIbETALMCABYACQmmIbETALMCAAAA.',
Me='Mehuman:BAAALgAECgQJCwAAAA==.Mehumanhuntr:BAAALgAECgQJBAAAAA==.Mehumanlock:BAABLgAECn8gAAIXAAgJ2hElCQBvAQAXAAgJ2hElCQBvAQAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgYJCgAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgYJCgAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Mordaci:BAAALgADCgQJBQABLgAECggJDAAEAAAAAA==.Mortstan:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgEJAQAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8cAAIGAAgJxRZLTQDAAQAGAAgJxRZLTQDAAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECggJIwAFAIIPAA==.Narie:BAAALgADCgYJBgAAAA==.Nasaug:BAAALgAECgUJBwABLgAECggJLQARAFYQAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAAALgAECgQJDAAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAYJFgADACAcAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAYJFgADACAcAA==.Noahvoker:BAAALgAECggJEQABLgAFFAYJFgADACAcAA==.Noahwarlock:BAACLgAFFH8WAAQDAAYJIBxVDwBkAQADAAUJuR9VDwBkAQAXAAIJsxR9CwCdAAAiAAEJkSMZDQBXAAAuAAQKfyoABAMACQnsI7kEACIDAAMACAlwI7kEACIDABcABAl0IkEaAHsBACIAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgUJCwAEAAAAAA==.Nook:BAAALgADCgUJBgAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJCwAAAA==.',
Oh='Ohmylantä:BAABLgAECn8dAAIWAAgJPg1bawBuAQAWAAgJPg1bawBuAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIQAAkJcRr4HgBTAgAQAAkJcRr4HgBTAgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orator:BAAALgAFFAIJAQAAAA==.Orbeck:BAAALgAECggJCAABLgAFFAYJGQAJAI8fAA==.Ormond:BAAALgAECgYJCgAAAA==.Orochinchin:BAAALgAECgMJAwABLgAFFAYJGgAdAB4lAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8cAAIjAAgJOwvlDwAGAQAjAAgJOwvlDwAGAQAAAA==.',
Pa='Pachane:BAAALgAECgQJCAAAAA==.Paldozer:BAAALgAECgUJBwABLgAECgUJCQAEAAAAAA==.Pallywacker:BAABLgAECn8kAAIRAAgJ1hGgEABvAQARAAgJ1hGgEABvAQAAAA==.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.',
Pi='Pigishdog:BAABLgAECn86AAIDAAgJPRteJAAbAgADAAgJPRteJAAbAgAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethemonk:BAAALgAECgEJBgAAAA==.Poshingtang:BAABLgAECn8pAAQFAAkJqgy/MQCfAQAFAAkJqgy/MQCfAQAIAAgJHhG8NgB4AQAVAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgADCggJDQAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8jAAIFAAgJgg+JQgB3AQAFAAgJgg+JQgB3AQAAAA==.',
Ra='Rabidbutt:BAAALgAFFAIJAwABLgAFFAUJEAAMALEkAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBiJmQD7AAACAAUJDBiJmQD7AAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygIFTgC5AAAKAAYJygIFTgC5AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAYJFwAIADITAA==.Ripndip:BAAALgAFFAIJAQAAAA==.Riprock:BAAALgAECgIJAQABLgAFFAIJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJLgADAPwcAA==.',
Rn='Rn:BAACLgAFFH8FAAIPAAQJShh2CgA3AQAPAAQJShh2CgA3AQAuAAQKfx4AAw8ACQklIkEBAEYDAA8ACQkIIkEBAEYDABgABwkvIyQpABcCAAEuAAUUCAkiAA8AfSQA.',
Ro='Roguehiro:BAABLgAECn8ZAAIRAAgJUxw1BwBuAgARAAgJUxw1BwBuAgAAAA==.Rooter:BAACLgAFFH8QAAIMAAUJsST4BAAKAgAMAAUJsST4BAAKAgAuAAQKfzQAAwwACAmPJcUCAAIDAAwACAmPJcUCAAIDAAsABwkmGZEfAJcBAAAA.Rosalynñ:BAABLgAECn8eAAIXAAgJZgeQEAD2AAAXAAgJZgeQEAD2AAAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQABLgAFFAIJAQAEAAAAAA==.',
Sa='Saelis:BAACLgAFFH8PAAINAAQJFhcKHAAmAQANAAQJFhcKHAAmAQAuAAQKfx0AAw0ACQnAHhwWAIUCAA0ACQnAHhwWAIUCACAABgnwGWMNAI0BAAAA.Samshara:BAAALgADCgcJDAABLgAECggJKQAZAEIaAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgAECggJDwAAAA==.Seong:BAACLgAFFH8ZAAIJAAYJjx9EBQDFAQAJAAYJjx9EBQDFAQAuAAQKfyEAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAYJGQAJAI8fAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgUJBwABLgAECgkJIwAeAJ4LAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAAALgADCgkJCQABLgAECggJKgAKAOkeAA==.Shamynna:BAAALgAECgIJAwAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8nAAITAAkJJxI4KgDxAQATAAkJJxI4KgDxAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shockawar:BAACLgAFFH8VAAIYAAUJeRwxAwDEAQAYAAUJeRwxAwDEAQAuAAQKfxQAAhgACQmrHmYYAIgCABgACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8TAAQZAAUJqSGFBQB5AQAZAAQJXyCFBQB5AQAUAAMJIiDGEAAqAQATAAQJfRvhNQD0AAAuAAQKfxsABBMACAk8IdMVAIkCABMABwnxIdMVAIkCABQABwlKIcoaAFMCABkAAwm3IQ4mAC4BAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8UAAIWAAYJ5gM2ygDDAAAWAAYJ5gM2ygDDAAAAAA==.Slootar:BAABLgAECn8UAAQNAAcJ5xuIJAAoAgANAAcJ5xuIJAAoAgAeAAIJuxBfbABuAAAgAAIJMAYHNgAyAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIhAAgJ7xb8FQAUAgAhAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn8pAAIZAAgJQhrGDgAKAgAZAAgJQhrGDgAKAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sugerlumps:BAAALgAECggJAgAAAA==.Sunstrike:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgQJBAAAAA==.Takka:BAABLgAECn8aAAIFAAgJHB06DwCUAgAFAAgJHB06DwCUAgAAAA==.Talden:BAABLgAECn8vAAMQAAgJkhpHPADWAQAQAAgJkhpHPADWAQARAAEJ/AW7RAAsAAAAAA==.Talkamar:BAABLgAECn8gAAIcAAgJlxA6HgB4AQAcAAgJlxA6HgB4AQAAAA==.Taylorswift:BAABLgAECn8nAAIWAAkJjRabKQA5AgAWAAkJjRabKQA5AgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn8nAAIRAAkJ6QjzFQArAQARAAkJ6QjzFQArAQAAAA==.Thenard:BAABLgAECn8cAAITAAgJOxNQOgCwAQATAAgJOxNQOgCwAQAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAMJBwAWAPoPAA==.Thukunamage:BAACLgAFFH8HAAIWAAMJ+g+XWwDxAAAWAAMJ+g+XWwDxAAAuAAQKfycAAhYACQk/IDMXAJwCABYACQk/IDMXAJwCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgQJBAAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8cAAQDAAkJ8xC1QACoAQADAAcJ0hC1QACoAQAXAAMJQxVMTwCAAAAiAAEJlA41JwA7AAAAAA==.Touritos:BAABLgAECn8WAAIIAAgJyg6BLwA4AQAIAAgJyg6BLwA4AQAAAA==.',
Tr='Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgADCgcJBwAAAA==.Tunk:BAAALgAFFAIJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMkAAgJ6RbMEwB4AgAkAAgJ6RbMEwB4AgAlAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAIJAQAAAA==.Tyler:BAACLgAFFH8LAAIGAAQJfhXYDwBPAQAGAAQJfhXYDwBPAQAuAAQKfxsAAgYACAkOHTgcAKkCAAYACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAAALgAECgQJDAAAAA==.',
Um='Umariel:BAAALgAFFAIJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBAAAAA==.Valr:BAABLgAECn8tAAIRAAgJVhBOFgAnAQARAAgJVhBOFgAnAQAAAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8PAAIWAAQJSA13QQA5AQAWAAQJSA13QQA5AQAuAAQKfy4AAhYACAl8GwU0AA8CABYACAl8GwU0AA8CAAAA.Vsesosorry:BAABLgAFFH8HAAIFAAQJjAWZLwDOAAAFAAQJjAWZLwDOAAABLgAFFAQJDwAWAEgNAA==.Vsè:BAAALgADCgUJBQABLgAFFAQJDwAWAEgNAA==.',
Vy='Vyke:BAAALgAECgYJBwABLgAFFAYJGQAJAI8fAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJDAAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAYJGgAdAB4lAA==.',
Wo='Worgenkrantz:BAABLgAECn8jAAMeAAkJngu6IAB1AQAeAAkJngu6IAB1AQANAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8QAAIHAAUJ5RXXBwA6AQAHAAUJ5RXXBwA6AQAuAAQKfzAAAwcACAlrI+0IAE8CAAcACAnsH+0IAE8CACMAAglDE64bAHcAAAAA.',
Xo='Xolòtl:BAABLgAECn8eAAIOAAgJhRYZFADLAQAOAAgJhRYZFADLAQABLgAFFAUJEAAHAOUVAA==.Xoss:BAAALgAFFAIJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAWAJIaAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zakuso:BAAALgAECgQJCQAAAA==.Zalyia:BAABLgAECn8rAAIaAAgJSQ2RJABcAQAaAAgJSQ2RJABcAQAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIWAAgJcBVpaQADAgAWAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8aAAQmAAgJNBeiDQAAAgAmAAcJChiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJGgAmADQXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIGAAgJORqFMAA5AgAGAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQQAAUJQBZTlgAKAQAQAAQJxhhTlgAKAQAKAAMJyRCQcgCxAAARAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgUJCAAAAA==.',
['Àn']='Àngron:BAAALgADCgUJBgAAAA==.',
['Âr']='Ârtemis:BAAALgAECgYJCwAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
['ßa']='ßaroness:BAAALgADCgUJCQAAAA==.',
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
