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

local lookup = {'Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Mage-Fire','Priest-Holy','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abeloth:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.',
Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAICAAgJQxcOjwBXAQACAAgJQxcOjwBXAQAAAA==.Allorna:BAAALgAECgcJBwAAAA==.',
An='Angelona:BAACLgAFFH8bAAICAAUJGSS4NwCNAQACAAUJGSS4NwCNAQAuAAQKfyMAAgIACAkcJmQNAFoDAAIACAkcJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn9AAAMDAAkJmCDDCwDQAgADAAkJmCDDCwDQAgAEAAEJ9gljpQErAAABLgAECgYJCQAFAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAACLgAFFH8FAAQDAAMJ+gWCPQBnAAADAAIJkAiCPQBnAAAEAAEJlwb5twBBAAAGAAIJUgAhGwAkAAAuAAQKfyMABAQACAm+GcI2AEgCAAQACAkSGcI2AEgCAAMABQlWFLpBADoBAAYAAwk1GW0oANEAAAAA.Archmond:BAABLgAECn8VAAMHAAcJJhczCwCIAQAHAAYJPxUzCwCIAQAIAAMJVROtPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCgAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8lAAIDAAgJqhnjGAA+AgADAAgJqhnjGAA+AgAAAA==.Ashthundér:BAABLgAECn8WAAIJAAYJKhj7BACpAQAJAAYJKhj7BACpAQABLgAFFAcJDgAKANwVAA==.',
Av='Avyhn:BAACLgAFFH8dAAQHAAcJciZaAQC6AQAKAAYJZiVEEgAdAgAHAAUJ5yRaAQC6AQAIAAEJ6ibTFgB2AAAuAAQKfyAAAwoACQmhJfYCAGIDAAoACAmhJfYCAGIDAAgAAgl3JONBAK0AAAEuAAUUCAk1AAcAgyYA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
['Aë']='Aëolus:BAAALgADCgYJBgAAAA==.',
Ba='Baaka:BAABLgAECn81AAMLAAgJRxDmWwCOAQALAAgJRxDmWwCOAQAMAAEJyQGvagAiAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Bale:BAAALgAECgkJCQAAAA==.Barquiel:BAABLgAECn80AAMGAAkJ6h3vBgBxAgAGAAkJ6h3vBgBxAgAEAAYJbQzKrAAiAQAAAA==.Batimo:BAAALgAECgQJBAAAAA==.Bayle:BAAALgADCgMJAwAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8mAAMNAAkJPh6GCgDHAgANAAkJPh6GCgDHAgAOAAEJNQt8jAAsAAAAAA==.Belyne:BAAALgAECgEJAgABLgAECgkJJgANAD4eAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.Biological:BAAALgAECgEJAQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAACLgAFFH8TAAMPAAQJcgx1EwDrAAAQAAQJ/QuyhgD3AAAPAAQJOAV1EwDrAAAuAAQKfxUAAxAACQkMF9dwAIEBABAACQkMF9dwAIEBABEABgl3B3NAAIsAAAAA.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgAFAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8fAAISAAgJ0hjhIQA3AgASAAgJ0hjhIQA3AgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMTAAgJlRhXNQDUAQATAAcJ7BtXNQDUAQAUAAUJZg9ONADxAAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAIQAAkJXRfBRAAnAgAQAAkJXRfBRAAnAgAAAA==.Bullthing:BAACLgAFFH8GAAMDAAIJ1xvGMwCcAAADAAIJ1xvGMwCcAAAEAAEJuQFqywAuAAAuAAQKfyoABAMACQnUIkMDAG0DAAMACQnUIkMDAG0DAAQABAkJFnffAM4AAAYAAQmLGx5FAE0AAAAA.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn85AAMVAAgJuSFoDACcAgAVAAgJuSFoDACcAgAWAAYJyx/kUgBkAQAAAA==.Cassyn:BAAALgAECgEJBAAAAA==.',
Ch='Chansey:BAABLgAECn8nAAINAAkJnB7fCACuAgANAAkJnB7fCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8sAAMXAAkJSx3dCgCFAgAXAAkJSx3dCgCFAgAYAAUJJwdaSQCzAAAAAA==.Chinchulin:BAAALgAECgQJAwAAAA==.Chipsbambee:BAABLgAECn8wAAILAAkJtg8uQgDZAQALAAkJtg8uQgDZAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8lAAMZAAcJpyLMAQDtAQAZAAYJfiTMAQDtAQAWAAUJExOxDAAPAQAuAAQKfzQAAxkACQnbJf8CAN4CABkACAk7Jv8CAN4CABYACQlGGcQiAA4CAAAA.',
Co='Combust:BAACLgAFFH8QAAICAAQJ6Rm8TABKAQACAAQJ6Rm8TABKAQAuAAQKf0MAAgIACQmgIloPAP4CAAIACQmgIloPAP4CAAAA.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgcJCgAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgAECgEJAQAAAA==.Dao:BAACLgAFFH8IAAIWAAMJzBR5EwDDAAAWAAMJzBR5EwDDAAAuAAQKfxUAAxYACAnEHMISAIACABYACAnEHMISAIACABUABAl+BDuFAGIAAAAA.Darelina:BAAALgADCgYJDQAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.Dayforce:BAAALgADCgYJBgAAAA==.',
De='Deathvader:BAAALgADCgcJDAAAAA==.Delaomega:BAABLgAECn86AAMRAAkJvQrzJQAhAQARAAkJvQrzJQAhAQAQAAEJjQYMfgEsAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvader:BAAALgAECgIJBAABLgAECgcJGwABABgMAA==.Drakvor:BAABLgAECn8uAAMRAAkJShXpCgBoAgARAAkJShXpCgBoAgAQAAEJcQHlOwEbAAAAAA==.Drash:BAABLgAECn9HAAMPAAgJqhZcCgDWAQAPAAgJwRVcCgDWAQARAAMJFBBdQQCHAAAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.Droni:BAAALgADCggJCAAAAA==.',
Du='Duhai:BAAALgAECgUJBAAAAA==.Dumbledore:BAABLgAECn8uAAIRAAkJfhv0DQAqAgARAAkJfhv0DQAqAgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgYJCAAAAA==.',
Ea='Eaterofholes:BAAALgAECgYJBwAAAA==.',
Ed='Edubijes:BAAALgAECgcJCgABLgAECggJHgATACkSAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgcJEwAAAA==.',
En='Endléss:BAABLgAECn8rAAIMAAgJOhqiFAAAAgAMAAgJOhqiFAAAAgAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAAFAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAEJAQAAAA==.',
Es='Eshwyn:BAAALgAECgYJBgAAAA==.Esquandolas:BAAALgADCgcJGAAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMBAAcJGAwXGQDkAAABAAcJGAwXGQDkAAAMAAUJZQb1QADCAAAAAA==.',
Fe='Fec:BAABLgAECn8bAAIZAAcJTx8bCQApAgAZAAcJTx8bCQApAgABLgAECgkJRgAaAP4fAA==.',
Fi='Fibaldrachi:BAABLgAECn8xAAIbAAkJ9SONAQAOAwAbAAkJ9SONAQAOAwAAAA==.',
Fl='Floorview:BAAALgAECgEJAQAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAACLgAFFH8LAAICAAMJixX1eADqAAACAAMJixX1eADqAAAuAAQKfyoAAgIACQk0IbgOAAMDAAIACQk0IbgOAAMDAAAA.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8bAAIVAAgJkh20GwACAgAVAAgJkh20GwACAgAAAA==.Ghiro:BAAALgAECgEJAQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDQAAAA==.',
Gr='Gradeabeef:BAAALgAECgUJBQAAAA==.Grandall:BAAALgAECgEJAwAAAA==.Grimsteel:BAAALgAECgMJAwAAAA==.Gruon:BAABLgAECn9IAAIcAAgJqg+ULABxAQAcAAgJqg+ULABxAQAAAA==.',
Gu='Gulzan:BAACLgAFFH8GAAIVAAMJTwqMOQCkAAAVAAMJTwqMOQCkAAAuAAQKfyUAAhUACAkUFs4gANsBABUACAkUFs4gANsBAAEuAAUUAwkDAAUAAAAA.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8rAAIaAAkJTRYmDgAGAgAaAAkJTRYmDgAGAgAAAA==.Haymakerxd:BAABLgAECn8aAAIQAAgJxiPfCgAWAwAQAAgJxiPfCgAWAwAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Ho='Holybeard:BAAALgAECgQJBAAAAA==.',
Hu='Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8tAAQHAAkJ9RvgAwBQAgAHAAkJ9RvgAwBQAgAIAAQJ3BFYIQCgAAAKAAMJCgxX5QCSAAAAAA==.Hypernova:BAAALgAECgUJBQAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAFFAEJAQAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDQAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8qAAICAAgJHwgEngA8AQACAAgJHwgEngA8AQAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgkJEwAAAA==.Inspiremoon:BAABLgAECn8fAAILAAgJERIOWwCQAQALAAgJERIOWwCQAQAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ip='Ipak:BAAALgADCgEJAQAAAA==.',
Ir='Iranos:BAABLgAECn8nAAMEAAgJqiBxJgBpAgAEAAgJqiBxJgBpAgAGAAIJLgx0QQBYAAAAAA==.Irishpryde:BAAALgAECgEJAQAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQAFAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECggJHgATACkSAA==.',
Ji='Jimbe:BAAALgAECgEJAwAAAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgcJCgAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaimari:BAAALgADCgcJBwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAFFAEJAQAFAAAAAA==.Kanakana:BAABLgAECn8nAAIWAAgJlR9+FwCLAgAWAAgJlR9+FwCLAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAABLgAECn8YAAIGAAkJKgXqLAC2AAAGAAkJKgXqLAC2AAAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAABLgAECn8bAAIKAAgJhQPetQDcAAAKAAgJhQPetQDcAAAAAA==.Kistn:BAAALgADCgIJAgAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Korja:BAAALgAECgEJAQAAAA==.Kosmos:BAAALgAECgcJEAABLgAFFAMJBAAFAAAAAA==.',
Kr='Kreid:BAABLgAECn8cAAIYAAgJKRuQFAByAgAYAAgJKRuQFAByAgAAAA==.Kreìd:BAAALgADCgEJAQABLgAECggJHAAYACkbAA==.',
Ku='Kungfoupanda:BAAALgAECgIJAwAAAA==.',
Ky='Kyrr:BAAALgAFFAQJBAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8sAAIdAAkJoBW0MwD1AQAdAAkJoBW0MwD1AQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMeAAkJTh68DQCDAgAeAAkJTh68DQCDAgAfAAUJHBTxIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgAECgEJAwAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAACLgAFFH8GAAIOAAMJtgVcKQCtAAAOAAMJtgVcKQCtAAAuAAQKfzEAAg4ACQlJENMfAMcBAA4ACQlJENMfAMcBAAAA.Linestia:BAAALgAECgEJAgABLgAECgYJCwAFAAAAAA==.Littlewingz:BAABLgAECn8tAAIgAAkJUCQvAQCYAwAgAAkJUCQvAQCYAwAAAA==.',
Lo='Lobotomy:BAABLgAFFH8LAAITAAQJgQ3uJQAaAQATAAQJgQ3uJQAaAQAAAA==.Lockinflame:BAACLgAFFH8OAAIKAAcJ3BWaFwD5AQAKAAcJ3BWaFwD5AQAuAAQKfxYAAgoACAn4IToVAKUCAAoACAn4IToVAKUCAAAA.Lockinload:BAAALgAFFAMJAwAAAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgMJAwAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgAFAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Malsandre:BAAALgADCgUJBQABLgAECgkJLQAHAPUbAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Mawz:BAABLgAECn8aAAIZAAgJ2hwfDADuAQAZAAgJ2hwfDADuAQAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAACLgAFFH8JAAISAAIJQyIhOgDCAAASAAIJQyIhOgDCAAAuAAQKfyEAAhIACQnrImMJAPwCABIACQnrImMJAPwCAAAA.Meedlefinger:BAAALgAECgQJBQAAAA==.Megatonne:BAAALgADCgkJCQAAAA==.Melathia:BAABLgAECn8eAAIKAAkJQQmtdwBKAQAKAAkJQQmtdwBKAQAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Moaroak:BAAALgAFFAMJAwAAAA==.Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgkJCAAAAA==.',
Mu='Musclebear:BAACLgAFFH8JAAIhAAQJmQmXIgAKAQAhAAQJmQmXIgAKAQAuAAQKfxgAAiEACAkJF4caAMEBACEACAkJF4caAMEBAAAA.',
My='Mythaux:BAAALgADCgMJAwABLgAFFAEJAQAFAAAAAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Napalm:BAAALgAECgUJBQABLgAECgkJLgACAIYcAA==.Nashamadd:BAAALgADCgIJAgAAAA==.',
Ne='Neero:BAABLgAECn8kAAIdAAgJGxtYLAAUAgAdAAgJGxtYLAAUAgAAAA==.Nelena:BAABLgAECn9AAAIWAAgJOQpxWgBLAQAWAAgJOQpxWgBLAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJDAAAAA==.Nezhyt:BAABLgAECn8qAAMIAAgJ4B47BAA6AgAIAAgJKh47BAA6AgAHAAUJeh4wFgAVAQABLgAFFAEJAQAFAAAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMeAAkJNRb2GwD2AQAeAAkJNRb2GwD2AQAgAAIJewIVRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAACLgAFFH8NAAIZAAQJCiZmAgDAAQAZAAQJCiZmAgDAAQAuAAQKfxkAAhkABwnrJTEFAJECABkABwnrJTEFAJECAAEuAAUUCAkwAAIAUiQA.Notdragon:BAAALgADCgMJBQAAAA==.Notorious:BAABLgAECn8jAAMgAAkJgRbCBwB1AgAgAAkJgRbCBwB1AgAeAAMJYRCHaQCbAAAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pandalin:BAAALgAECgUJBQAAAA==.Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn84AAQeAAkJIhXDFQAqAgAeAAkJIhXDFQAqAgAgAAgJdwMtIADxAAAfAAIJPxLkGgBzAAAAAA==.',
Pe='Pelgryn:BAAALgADCgYJCwAAAA==.Pentasaurusr:BAABLgAECn8eAAMKAAcJSh+bQAAMAgAKAAYJSh+bQAAMAgAIAAIJ6BkiTACJAAAAAA==.',
Pl='Platemedic:BAAALgAECgYJBwAAAA==.',
Po='Polevik:BAAALgAFFAEJAQAAAA==.Pookkee:BAAALgAECgYJCwAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAwAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8eAAQTAAgJKRIsSQAhAQATAAcJuwwsSQAhAQAaAAQJZBMTLQDPAAAUAAQJ0gujYgBZAAAAAA==.',
Ra='Ratamahatta:BAAALgAECgUJBQAAAA==.Rayeona:BAAALgAECgYJDAAAAA==.',
Re='Recheals:BAAALgAECgkJCgAAAA==.Recmod:BAABLgAECn8dAAMhAAcJ+BjqJQBkAQAhAAcJ+BjqJQBkAQAiAAEJSxHKJAA/AAABLgAECgkJCgAFAAAAAA==.Recsdru:BAAALgAECgYJBgABLgAECgkJCgAFAAAAAA==.Rendover:BAAALgAECgYJBwAAAA==.Return:BAABLgAECn9GAAIaAAkJ/h+hBgCeAgAaAAkJ/h+hBgCeAgAAAA==.Reze:BAAALgAECgYJBwAAAA==.',
Rh='Rhimeholt:BAABLgAECn8gAAMYAAkJ7hpeEgCIAgAYAAkJ7hpeEgCIAgAjAAEJgQqpoAAtAAAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJBAAAAA==.Roxagar:BAAALgAECgUJCAABLgAECgcJGwABABgMAA==.',
Ry='Ryahask:BAABLgAECn8vAAIZAAkJwxFvDQDVAQAZAAkJwxFvDQDVAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticdk:BAAALgAECgkJAQABLgAFFAMJBwAEAOwSAA==.Sadisticrage:BAACLgAFFH8HAAIEAAMJ7BKaaADZAAAEAAMJ7BKaaADZAAAuAAQKf0MAAgQACQmtHyoVAMICAAQACQmtHyoVAMICAAAA.Sae:BAAALgAECgMJAwAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scottklam:BAAALgAECgYJCgAAAA==.Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMkAAkJ9B4KAwD4AQACAAgJLBpHbQD6AQAkAAcJZyEKAwD4AQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAgAAAA==.Selyste:BAAALgAECgQJBQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.Senthara:BAAALgAECggJEgAAAA==.',
Sh='Shadow:BAABLgAECn8bAAIQAAgJjhKmXwCoAQAQAAgJjhKmXwCoAQAAAA==.Shanaa:BAAALgAECgEJAQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.Shxggy:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slagathor:BAAALgAECgMJBAAAAA==.Slippie:BAAALgAECgMJAwAAAA==.Slipstreamer:BAAALgADCgEJAQAAAA==.',
Sm='Smell:BAABLgAECn9EAAIEAAkJkhmzMwAwAgAEAAkJkhmzMwAwAgAAAA==.',
So='Solheim:BAACLgAFFH8LAAIEAAMJ7SGFRAAfAQAEAAMJ7SGFRAAfAQAuAAQKfxYAAgQACAlTJR8VAMICAAQACAlTJR8VAMICAAAA.',
Sp='Spacemonk:BAAALgAECgQJCAAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8sAAMSAAkJkQmWTwBOAQASAAkJkQmWTwBOAQAcAAcJmgVaUADJAAAAAA==.',
St='Stearphen:BAABLgAECn8VAAMaAAkJYBW5EwCyAQAaAAkJYBW5EwCyAQATAAEJ5wOhsAAqAAAAAA==.Steze:BAAALgAECgEJAgAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJDwAAAA==.',
Sw='Swazti:BAABLgAECn8eAAIKAAgJUxL0WwCKAQAKAAgJUxL0WwCKAQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgkJCAAFAAAAAA==.Taurnil:BAACLgAFFH8MAAIHAAMJsQsQCgDXAAAHAAMJsQsQCgDXAAAuAAQKf0QAAgcACAmRG1cFADQCAAcACAmRG1cFADQCAAAA.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Teloiv:BAAALgADCggJBwAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Th='Thadontrump:BAAALgAECgMJBAAAAA==.',
Ti='Tibidari:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.Timika:BAABLgAECn8/AAMNAAkJoxmfHADoAQAlAAgJCxhzGgD0AQANAAcJGBafHADoAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Tr='Trales:BAAALgAECgYJBgAAAA==.',
Ty='Typeshift:BAABLgAFFH8QAAImAAUJlh95CABmAQAmAAUJlh95CABmAQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAcJIgAeAJIYAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAABLgAECn8VAAIQAAYJ2RVrjQBIAQAQAAYJ2RVrjQBIAQAAAA==.',
Va='Vaeron:BAABLgAECn8VAAIhAAcJ3htsGQDMAQAhAAcJ3htsGQDMAQAAAA==.',
Ve='Veckna:BAAALgADCgEJAQAAAA==.Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8uAAITAAkJzhNYIgDfAQATAAkJzhNYIgDfAQAAAA==.Venomsecho:BAABLgAECn8jAAInAAkJ2BQRDwDAAQAnAAkJ2BQRDwDAAQAAAA==.Venomshexo:BAAALgAECgEJAQAAAA==.Verboux:BAAALgAECgIJBAAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAwAAAA==.Videl:BAAALgAECgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECggJEQAAAA==.',
We='Weathergirl:BAABLgAECn8bAAMWAAkJnxFTMADxAQAWAAkJnxFTMADxAQAVAAYJTBv6SAAkAQAAAA==.',
Wh='Whisky:BAAALgAECgYJCQAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIYAAgJ0BiZFwADAgAYAAgJ0BiZFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgYJFQAYAIgfAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAAFAAAAAA==.Worshipme:BAAALgAECgYJBwAAAA==.',
Wy='Wy:BAAALgAECgcJEQAAAA==.',
Xa='Xanna:BAAALgAFFAIJAgAAAA==.',
Xh='Xhaman:BAAALgAECgEJAQABLgAFFAMJBwAFAAAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIGAAMJGhP4AwCeAAAGAAMJGhP4AwCeAAAuAAQKfycAAgYACAmlItwCAPsCAAYACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAACLgAFFH8KAAMKAAUJtQMweADPAAAKAAUJtQMweADPAAAIAAEJAADYLQAAAAAuAAQKfx4AAwoACQnREFs/AN8BAAoACQnREFs/AN8BAAgAAQmYB5B2AC4AAAAA.',
Za='Zach:BAABLgAECn8uAAICAAkJhhw7IQCXAgACAAkJhhw7IQCXAgAAAA==.',
Ze='Zengang:BAAALgADCgEJAQABLgAECgkJRgAaAP4fAA==.',
Zm='Zmagez:BAAALgAECggJEgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIYAAcJiwVaPADzAAAYAAcJiwVaPADzAAAAAA==.',
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
