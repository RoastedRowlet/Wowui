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

local lookup = {'Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','DeathKnight-Frost','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','Priest-Holy','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-06-28',data={Ab='Abeloth:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.',
Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAICAAgJQxdskABXAQACAAgJQxdskABXAQAAAA==.Alfurius:BAAALgADCgEJAQAAAA==.Allorna:BAAALgAECgcJBwAAAA==.Alxe:BAAALgADCgYJBgAAAA==.',
An='Angelona:BAACLgAFFH8cAAICAAYJ/SCBOACIAQACAAYJ/SCBOACIAQAuAAQKfyQAAgIACQkxJmQNAFoDAAIACQkxJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn9FAAMDAAkJ7yGTAwBmAwADAAkJ7yGTAwBmAwAEAAEJ9gkftAEoAAABLgAECgYJCQAFAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAACLgAFFH8GAAQDAAMJjQ2APgBnAAADAAMJjQ2APgBnAAAEAAEJlwYQvABBAAAGAAIJUgDIGwAkAAAuAAQKfyQABAQACAm+GcI2AEgCAAQACAkSGcI2AEgCAAMABgndFSJCADkBAAYAAwk1GdIoANEAAAEuAAUUBAkTAAcAcgwA.Archmond:BAABLgAECn8VAAMIAAcJJhczCwCIAQAIAAYJPxUzCwCIAQAJAAMJVROtPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCgAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8lAAIDAAgJqhkoGQA9AgADAAgJqhkoGQA9AgAAAA==.Ashthundér:BAABLgAECn8WAAIKAAYJKhj7BACpAQAKAAYJKhj7BACpAQABLgAFFAcJEgALAI4WAA==.',
Av='Avyhn:BAACLgAFFH8dAAQIAAcJciZ1AQC4AQALAAYJZiUwFAAbAgAIAAUJ5yR1AQC4AQAJAAEJ6iZGFwB2AAAuAAQKfyAAAwsACQmhJSMDAGADAAsACAmhJSMDAGADAAkAAgl3JONBAK0AAAEuAAUUCQlBAAkADCMA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
['Aë']='Aëolus:BAAALgADCgYJBgAAAA==.',
Ba='Baaka:BAABLgAECn81AAMMAAgJRxAlXQCOAQAMAAgJRxAlXQCOAQANAAEJyQHdawAiAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Bale:BAAALgAECgkJCQAAAA==.Barbatosrex:BAAALgAECgEJAQAAAA==.Barquiel:BAABLgAECn80AAMGAAkJ6h0PBwBwAgAGAAkJ6h0PBwBwAgAEAAYJbQzarwAfAQAAAA==.Batimo:BAAALgAECgQJBAAAAA==.Bayle:BAAALgADCgMJAwAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8nAAMOAAkJlx+vCgDEAgAOAAkJlx+vCgDEAgAPAAEJNQsxjgAsAAAAAA==.Belyne:BAAALgAECgEJAwABLgAECgkJJwAOAJcfAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.Biological:BAAALgAECgEJAQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAACLgAFFH8TAAMHAAQJcgwyFADrAAAQAAQJ/QuhiQD2AAAHAAQJOAUyFADrAAAuAAQKfxUAAxAACQkMF8FxAIABABAACQkMF8FxAIABABEABgl3B/BAAIsAAAAA.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgAFAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8fAAISAAgJ0hgxIgA3AgASAAgJ0hgxIgA3AgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMTAAgJlRhXNQDUAQATAAcJ7BtXNQDUAQAUAAUJZg8eNQDxAAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAIQAAkJXRfBRAAnAgAQAAkJXRfBRAAnAgAAAA==.Bucetaa:BAAALgAECgEJAQAAAA==.Bullthing:BAACLgAFFH8GAAMDAAIJ1xu1NACcAAADAAIJ1xu1NACcAAAEAAEJuQEe0AAuAAAuAAQKfyoABAMACQnUIlUDAGwDAAMACQnUIlUDAGwDAAQABAkJFnffAM4AAAYAAQmLG+dFAE0AAAAA.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn86AAMVAAgJuSGYDACbAgAVAAgJuSGYDACbAgAWAAYJyx/6UwBkAQAAAA==.Cassyn:BAAALgAECgEJBAAAAA==.Cathedrian:BAABLgAECn8ZAAIXAAgJ/xXxAgAoAQAXAAgJ/xXxAgAoAQAAAA==.',
Ch='Chansey:BAABLgAECn8nAAIOAAkJnB7fCACuAgAOAAkJnB7fCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8uAAQYAAkJSx38CgCEAgAYAAkJSx38CgCEAgAZAAYJrAdaSQCzAAAaAAEJzQWHEwAgAAAAAA==.Chinchulin:BAAALgAECgQJAwAAAA==.Chipsbambee:BAABLgAECn8xAAIMAAkJtg9LQwDYAQAMAAkJtg9LQwDYAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8lAAMbAAcJpyLnAQDrAQAbAAYJfiTnAQDrAQAWAAUJExOxDAAPAQAuAAQKfzQAAxsACQnbJQ4DAN0CABsACAk7Jg4DAN0CABYACQlGGcQiAA4CAAAA.',
Co='Combust:BAACLgAFFH8QAAICAAQJ6RmYTgBBAQACAAQJ6RmYTgBBAQAuAAQKf0MAAgIACQmgIqsPAP4CAAIACQmgIqsPAP4CAAAA.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgcJCgAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgAECgEJAQAAAA==.Dao:BAACLgAFFH8IAAIWAAMJzBR5EwDDAAAWAAMJzBR5EwDDAAAuAAQKfxUAAxYACAnEHMISAIACABYACAnEHMISAIACABUABAl+BBuHAGEAAAAA.Darelina:BAAALgADCgYJDQAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.Dayforce:BAAALgADCgYJBgAAAA==.',
De='Deathvader:BAAALgADCgcJDAAAAA==.Delaomega:BAABLgAECn9CAAMRAAkJDAvBAwDcAAARAAkJDAvBAwDcAAAQAAEJjQYLgwEsAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJCgAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Dimpowa:BAAALgAECgYJBwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvader:BAAALgAECgIJBAABLgAECgcJGwABABgMAA==.Drakvor:BAABLgAECn8uAAMRAAkJShXpCgBoAgARAAkJShXpCgBoAgAQAAEJcQHlOwEbAAAAAA==.Drash:BAABLgAECn9IAAMHAAgJMRenCgDSAQAHAAgJSBanCgDSAQARAAMJFBD2QQCHAAAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.Droni:BAAALgADCggJCAAAAA==.',
Du='Duhai:BAAALgAECgUJBQAAAA==.Dumbledore:BAABLgAECn8vAAIRAAkJyhstDQA4AgARAAkJyhstDQA4AgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgYJCAAAAA==.',
Ea='Eaterofholes:BAAALgAECgYJBwAAAA==.',
Ed='Edubijes:BAAALgAECgcJCgABLgAECggJHgATACkSAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgcJEwAAAA==.',
En='Endléss:BAABLgAECn8rAAINAAgJOhoaFQD7AQANAAgJOhoaFQD7AQAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAAFAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAIJAwAAAA==.',
Es='Eshwyn:BAAALgAECgYJBgAAAA==.Esquandolas:BAAALgADCgcJGAAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMBAAcJGAxeGQDkAAABAAcJGAxeGQDkAAANAAUJZQa3QQC+AAAAAA==.',
Fa='Faylana:BAAALgAECgEJAQABLgAECgkJLwARAMobAA==.',
Fe='Fec:BAABLgAECn8bAAIbAAcJTx9FCQApAgAbAAcJTx9FCQApAgABLgAECgkJRgAcAP4fAA==.',
Fi='Fibaldrachi:BAABLgAECn8zAAIdAAkJBCSTAQANAwAdAAkJBCSTAQANAwAAAA==.',
Fl='Floorview:BAAALgAECgEJAQAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAACLgAFFH8LAAICAAMJixVAegDjAAACAAMJixVAegDjAAAuAAQKfyoAAgIACQk0IQUPAAIDAAIACQk0IQUPAAIDAAAA.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8bAAIVAAgJkh0EHAABAgAVAAgJkh0EHAABAgAAAA==.Ghiro:BAAALgAECgEJAQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDQAAAA==.',
Gr='Gradeabeef:BAAALgAECgUJBQAAAA==.Grandall:BAAALgAECgEJAwAAAA==.Grimsteel:BAAALgAECgMJAwAAAA==.Gruon:BAABLgAECn9JAAIeAAgJ7hACLQBxAQAeAAgJ7hACLQBxAQAAAA==.',
Gu='Gulzan:BAACLgAFFH8GAAIVAAMJTwr5OgCkAAAVAAMJTwr5OgCkAAAuAAQKfyUAAhUACAkUFlohANkBABUACAkUFlohANkBAAEuAAUUBAkHAAwAIxUA.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8vAAIcAAkJihdhDgAFAgAcAAkJihdhDgAFAgAAAA==.Haymakerxd:BAACLgAFFH8FAAIQAAEJqhWiEQFBAAAQAAEJqhWiEQFBAAAuAAQKfxoAAhAACAnGIykLABUDABAACAnGIykLABUDAAAA.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Hu='Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8tAAQIAAkJ9RvgAwBQAgAIAAkJ9RvgAwBQAgAJAAQJ3BHcIQCgAAALAAMJCgwn6ACOAAAAAA==.Hypernova:BAAALgAECgUJBQAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAFFAEJAQAAAA==.Icewalker:BAAALgADCgUJBQAAAA==.Icyenic:BAAALgADCgEJAQAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDQAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8rAAICAAgJdghznwA8AQACAAgJdghznwA8AQAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgkJEwAAAA==.Inspiremoon:BAABLgAECn8hAAIMAAkJbxGEOwDxAQAMAAkJbxGEOwDxAQAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ip='Ipak:BAAALgADCgEJAQAAAA==.',
Ir='Iranos:BAABLgAECn8nAAMEAAgJqiD/JgBoAgAEAAgJqiD/JgBoAgAGAAIJLgwUQgBYAAAAAA==.Irishpryde:BAAALgAECgEJAQAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQAFAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECggJHgATACkSAA==.',
Ji='Jimbe:BAAALgAECgEJAwAAAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgcJCgAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaimari:BAAALgADCgcJBwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAFFAEJAQAFAAAAAA==.Kanakana:BAABLgAECn8nAAIWAAgJlR/hFwCKAgAWAAgJlR/hFwCKAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAABLgAECn8YAAIGAAkJKgVcLQC2AAAGAAkJKgVcLQC2AAAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAABLgAECn8fAAILAAkJTwRhEQBkAAALAAkJTwRhEQBkAAAAAA==.Kistn:BAAALgADCgIJAgAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Korja:BAAALgAECgEJAQAAAA==.Kosmos:BAAALgAECgcJEAABLgAFFAUJCQAZANQVAA==.',
Kr='Kreid:BAABLgAECn8gAAIZAAkJ4Br1FABzAgAZAAkJ4Br1FABzAgAAAA==.Kreìd:BAAALgADCgEJAQABLgAECgkJIAAZAOAaAA==.',
Ku='Kungfoupanda:BAAALgAECgIJAwAAAA==.',
Ky='Kyrr:BAAALgAFFAQJBAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8wAAIfAAkJxxeyBQApAQAfAAkJxxeyBQApAQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMgAAkJTh7YDQCDAgAgAAkJTh7YDQCDAgAhAAUJHBTxIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgAECgEJAwAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAACLgAFFH8KAAIPAAMJtgWNCwChAAAPAAMJtgWNCwChAAAuAAQKfzEAAg8ACQlJENQgAL8BAA8ACQlJENQgAL8BAAAA.Linestia:BAAALgAECgEJAgABLgAECgYJCwAFAAAAAA==.Littlewingz:BAABLgAECn8tAAIiAAkJUCQyAQCYAwAiAAkJUCQyAQCYAwAAAA==.',
Lo='Lobotomy:BAABLgAFFH8LAAITAAQJgQ3gJgAaAQATAAQJgQ3gJgAaAQAAAA==.Lockinflame:BAACLgAFFH8SAAILAAcJjhaHGQD3AQALAAcJjhaHGQD3AQAuAAQKfxYAAgsACAn4IaYVAKMCAAsACAn4IaYVAKMCAAAA.Lockinload:BAAALgAFFAMJAwABLgAFFAQJEwAHAHIMAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgMJAwAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgAFAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Malsandre:BAAALgADCgUJBQABLgAECgkJLQAIAPUbAA==.Mascro:BAAALgAECgYJCgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Mawz:BAABLgAECn8aAAIbAAgJ2hxlDADsAQAbAAgJ2hxlDADsAQAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAACLgAFFH8JAAISAAIJQyI3OwDBAAASAAIJQyI3OwDBAAAuAAQKfyEAAhIACQnrImMJAPwCABIACQnrImMJAPwCAAAA.Meedlefinger:BAAALgAECgQJBQAAAA==.Megatonne:BAAALgADCgkJCQAAAA==.Melathia:BAABLgAECn8gAAILAAkJkglMeQBGAQALAAkJkglMeQBGAQAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mi='Mistrunner:BAAALgAECgEJAQAAAA==.',
Mo='Moaroak:BAABLgAFFH8HAAIMAAQJIxUjDgA4AQAMAAQJIxUjDgA4AQAAAA==.Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgkJCwAAAA==.',
Mu='Musclebear:BAACLgAFFH8JAAIjAAQJmQlPIwAKAQAjAAQJmQlPIwAKAQAuAAQKfxgAAiMACAkJF9caAMEBACMACAkJF9caAMEBAAAA.',
My='Mythaux:BAAALgADCgMJAwABLgAFFAEJAQAFAAAAAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Napalm:BAAALgAECgUJBQABLgAECgkJLgACAIYcAA==.Nashamadd:BAAALgADCgIJAgAAAA==.',
Ne='Neero:BAABLgAECn8kAAIfAAgJGxvYLAAUAgAfAAgJGxvYLAAUAgAAAA==.Nelena:BAABLgAECn9AAAIWAAgJOQp8WwBLAQAWAAgJOQp8WwBLAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJDAAAAA==.Nezhyt:BAABLgAECn8sAAMJAAkJdR9ZBAA6AgAJAAkJ1R5ZBAA6AgAIAAUJeh54FgAVAQABLgAFFAEJAQAFAAAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMgAAkJNRZlHADyAQAgAAkJNRZlHADyAQAiAAIJewIVRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Noodles:BAAALgAECgYJBgABLgAECggJIgAfAH0WAA==.Nori:BAACLgAFFH8WAAIbAAUJCiYJAQBtAQAbAAUJCiYJAQBtAQAuAAQKfxkAAhsABwnrJUwFAJACABsABwnrJUwFAJACAAEuAAUUCQkzAAIA7CIA.Norrismonje:BAAALgAECgMJCQAAAA==.Notdragon:BAAALgADCgMJBQAAAA==.Notorious:BAABLgAECn8jAAMiAAkJgRbaBwB2AgAiAAkJgRbaBwB2AgAgAAMJYRDTagCbAAAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Ny='Ny:BAAALgAECgMJAwABLgAECgcJEwAFAAAAAA==.',
Ob='Obesitree:BAAALgAECgEJAgAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pandalin:BAAALgAECgUJBQAAAA==.Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn9AAAQgAAkJ0hgjAgBRAQAgAAkJ0hgjAgBRAQAiAAkJ+AN3IADxAAAhAAIJPxIuGwBzAAAAAA==.',
Pe='Pelgryn:BAAALgADCgYJCwAAAA==.Pentasaurusr:BAABLgAECn8eAAMLAAcJSh+bQAAMAgALAAYJSh+bQAAMAgAJAAIJ6BkiTACJAAAAAA==.',
Pl='Placebø:BAAALgAECgcJCgAAAA==.Platemedic:BAAALgAECgYJCAAAAA==.',
Po='Polevik:BAAALgAFFAEJAQAAAA==.Pookkee:BAAALgAECgYJCwAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAwAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8eAAQTAAgJKRLLSgAbAQATAAcJuwzLSgAbAQAcAAQJZBOCLQDPAAAUAAQJ0gtMZABZAAAAAA==.',
Ra='Ratamahatta:BAAALgAECgUJBQAAAA==.Rayeona:BAAALgAECgYJDAAAAA==.',
Re='Recheals:BAAALgAECgkJCgAAAA==.Recmod:BAABLgAECn8eAAMjAAgJexdKJgBkAQAjAAgJexdKJgBkAQAkAAEJSxErJQA/AAABLgAECgkJCgAFAAAAAA==.Recsdru:BAAALgAECggJCQABLgAECgkJCgAFAAAAAA==.Regulargal:BAAALgADCgYJCgABLgAECgcJAgAFAAAAAA==.Rendover:BAAALgAECgYJBwAAAA==.Return:BAABLgAECn9GAAIcAAkJ/h+5BgCdAgAcAAkJ/h+5BgCdAgAAAA==.Reze:BAAALgAECgYJCQAAAA==.',
Rh='Rhimeholt:BAABLgAECn8gAAMZAAkJ7hqqEgCIAgAZAAkJ7hqqEgCIAgAaAAEJgQriogAtAAAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJBAAAAA==.Roxagar:BAAALgAECgUJCAABLgAECgcJGwABABgMAA==.',
Ry='Ryahask:BAABLgAECn8vAAIbAAkJwxGvDQDUAQAbAAkJwxGvDQDUAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticdk:BAAALgAECgkJAQABLgAFFAMJDQAEAJYVAA==.Sadisticrage:BAACLgAFFH8NAAIEAAMJlhXSGgDNAAAEAAMJlhXSGgDNAAAuAAQKf0MAAgQACQmtH40VAMECAAQACQmtH40VAMECAAAA.Sae:BAAALgAECgMJAwAAAA==.Sakukoivu:BAAALgADCgEJAQAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scottklam:BAAALgAECgYJCgAAAA==.Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMlAAkJ9B4KAwD4AQACAAgJLBpHbQD6AQAlAAcJZyEKAwD4AQAAAA==.Sekhmet:BAAALgAECgYJBwAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAgAAAA==.Selyste:BAAALgAECgQJBQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.Senthara:BAAALgAECggJEgAAAA==.',
Sg='Sgtoricalcos:BAAALgADCgcJBwAAAA==.',
Sh='Shadow:BAABLgAECn8bAAIQAAgJjhJ+YACoAQAQAAgJjhJ+YACoAQAAAA==.Shanaa:BAAALgAECgEJAQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.Shxggy:BAAALgAECgEJAQAAAA==.',
Si='Sillygoober:BAAALgAECgQJBwAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slagathor:BAAALgAECgMJBAAAAA==.Slain:BAAALgAECgEJAQAAAA==.Slippie:BAAALgAECgMJAwAAAA==.Slipstreamer:BAAALgADCgEJAQAAAA==.',
Sm='Smell:BAABLgAECn9MAAIEAAkJ9BouBQCEAQAEAAkJ9BouBQCEAQAAAA==.',
So='Solheim:BAACLgAFFH8LAAIEAAMJ7SFQRwAdAQAEAAMJ7SFQRwAdAQAuAAQKfxYAAgQACAlTJYgVAMECAAQACAlTJYgVAMECAAAA.',
Sp='Spacemonk:BAAALgAECgcJCwAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8uAAMSAAkJsgkaUABOAQASAAkJsgkaUABOAQAeAAcJmgVUUQDJAAAAAA==.',
St='Stearphen:BAABLgAECn8ZAAMcAAkJYBXyEwCxAQAcAAkJYBXyEwCxAQATAAEJ5wOhsAAqAAAAAA==.Steze:BAAALgAECgMJBQAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJDwAAAA==.',
Sw='Swazti:BAABLgAECn8eAAILAAgJUxKvXQCGAQALAAgJUxKvXQCGAQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgkJCwAFAAAAAA==.Taurnil:BAACLgAFFH8NAAIIAAMJEgw9CgDYAAAIAAMJEgw9CgDYAAAuAAQKf0QAAggACAmRG2kFADMCAAgACAmRG2kFADMCAAAA.',
Te='Teacat:BAABLgAFFH8GAAIZAAIJYBXJGQB8AAAZAAIJYBXJGQB8AAABLgAFFAIJCQASAEMiAA==.Teledor:BAAALgAECgQJBgAAAA==.Teloiv:BAAALgADCggJBwAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Th='Thadontrump:BAAALgAECgMJBAAAAA==.',
Ti='Tibidari:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.Timika:BAABLgAECn9KAAMOAAkJ7xnoHADnAQAmAAgJYBjAGgD0AQAOAAcJGBboHADnAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Tr='Trales:BAAALgAECgYJBgAAAA==.',
Ty='Typeshift:BAABLgAFFH8QAAIXAAUJlh/wCABlAQAXAAUJlh/wCABlAQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAcJIgAgAJIYAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAABLgAECn8VAAIQAAYJ2RWtjgBIAQAQAAYJ2RWtjgBIAQAAAA==.',
Va='Vaeron:BAABLgAECn8VAAIjAAcJ3hu3GQDMAQAjAAcJ3hu3GQDMAQAAAA==.',
Ve='Veckna:BAAALgADCgEJAQAAAA==.Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8uAAITAAkJzhOwIgDdAQATAAkJzhOwIgDdAQAAAA==.Venomsecho:BAABLgAECn8jAAInAAkJ2BQ4DwDCAQAnAAkJ2BQ4DwDCAQAAAA==.Venomshexo:BAAALgAECgEJAQAAAA==.Verboux:BAAALgAECgIJBAAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAwAAAA==.Videl:BAAALgAECgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECggJEQAAAA==.',
Vy='Vynn:BAAALgAECgMJAwABLgAECgcJEwAFAAAAAA==.',
We='Weathergirl:BAABLgAECn8bAAMWAAkJnxHmMADxAQAWAAkJnxHmMADxAQAVAAYJTBv6SAAkAQAAAA==.Westodrood:BAAALgAECgUJBQAAAA==.',
Wh='Whisky:BAAALgAECgYJCQAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIZAAgJ0BiZFwADAgAZAAgJ0BiZFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgYJFQAZAIgfAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAAFAAAAAA==.Worshipme:BAAALgAECgYJBwAAAA==.',
Wy='Wy:BAAALgAECgcJEwAAAA==.',
Xa='Xanna:BAAALgAFFAIJAgABLgAFFAQJEwAHAHIMAA==.',
Xh='Xhaman:BAAALgAECgEJAQABLgAFFAMJCgAFAAAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIGAAMJGhP4AwCeAAAGAAMJGhP4AwCeAAAuAAQKfycAAgYACAmlItwCAPsCAAYACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAACLgAFFH8MAAMLAAYJqQNKJwCMAAALAAYJqQNKJwCMAAAJAAEJAACZLgAAAAAuAAQKfx4AAwsACQnREMM/AN4BAAsACQnREMM/AN4BAAkAAQmYB5B2AC4AAAAA.',
Za='Zach:BAABLgAECn8uAAICAAkJhhzGIQCWAgACAAkJhhzGIQCWAgAAAA==.',
Ze='Zengang:BAAALgAECgUJDAABLgAECgkJRgAcAP4fAA==.',
Zm='Zmagez:BAAALgAECggJEgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIZAAcJiwVaPADzAAAZAAcJiwVaPADzAAAAAA==.',
['Ðe']='Ðeath:BAAALgAECgUJBQAAAA==.',
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
