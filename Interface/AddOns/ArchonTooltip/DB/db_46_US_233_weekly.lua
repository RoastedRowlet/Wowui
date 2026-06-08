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

local lookup = {'Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Outlaw','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Frost','Warrior-Protection','DemonHunter-Vengeance','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Monk-Windwalker','Mage-Fire','Priest-Holy','Druid-Guardian','Druid-Feral',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Abeloth:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.',
Ac='Achlyss:BAAALgAECgEJAQAAAA==.',
Ad='Adanto:BAAALgADCgEJAQAAAA==.Addequation:BAAALgAECgIJBQAAAA==.Adivh:BAAALgADCgEJAQAAAA==.',
Ah='Ahtreyou:BAAALgADCgIJAgAAAA==.',
Al='Alatär:BAABLgAECn8aAAICAAgJQxdyjQBYAQACAAgJQxdyjQBYAQAAAA==.Allorna:BAAALgAECgcJBwAAAA==.',
An='Angelona:BAACLgAFFH8bAAICAAUJGSSRMACWAQACAAUJGSSRMACWAQAuAAQKfyMAAgIACAkcJmQNAFoDAAIACAkcJmQNAFoDAAAA.Angelonah:BAAALgAECgQJBAAAAA==.Angelsenvy:BAABLgAECn9AAAMDAAkJmCAQCwDSAgADAAkJmCAQCwDSAgAEAAEJ9gmYlgErAAABLgAECgYJCQAFAAAAAA==.Anthela:BAAALgADCgcJBwAAAA==.',
Ar='Arabeth:BAAALgADCgMJAgAAAA==.Archadis:BAACLgAFFH8FAAQDAAMJ+gWxOgBtAAADAAIJkAixOgBtAAAEAAEJlwbbrQBBAAAGAAIJUgB4GQApAAAuAAQKfyMABAQACAm+GcI2AEgCAAQACAkSGcI2AEgCAAMABQlWFOQ/ADoBAAYAAwk1Gf0mANIAAAAA.Archmond:BAABLgAECn8VAAMHAAcJJhczCwCIAQAHAAYJPxUzCwCIAQAIAAMJVROtPgC6AAAAAA==.Ardric:BAAALgADCgEJAQAAAA==.Arthek:BAAALgAECgUJCgAAAA==.',
As='Ashes:BAAALgAECgEJAQAAAA==.Ashteru:BAABLgAECn8lAAIDAAgJqhnzFwA/AgADAAgJqhnzFwA/AgAAAA==.Ashthundér:BAABLgAECn8WAAIJAAYJKhj7BACpAQAJAAYJKhj7BACpAQABLgAFFAQJCAAKAOMaAA==.',
Av='Avyhn:BAACLgAFFH8VAAMKAAYJZiUhDgAjAgAKAAYJZiUhDgAjAgAHAAEJAADkKwAAAAAuAAQKfyAAAwoACQmhJZ0CAGUDAAoACAmhJZ0CAGUDAAgAAgl3JONBAK0AAAEuAAUUCAk1AAoAgyYA.',
Az='Azlia:BAAALgAECgUJBQAAAA==.',
['Aë']='Aëolus:BAAALgADCgYJBgAAAA==.',
Ba='Baaka:BAABLgAECn81AAMLAAgJRxDfVgCUAQALAAgJRxDfVgCUAQAMAAEJyQFxZwAjAAAAAA==.Bahumat:BAAALgADCgMJAwAAAA==.Bale:BAAALgAECgkJCQAAAA==.Barquiel:BAABLgAECn80AAMGAAkJ6h17BgBzAgAGAAkJ6h17BgBzAgAEAAYJbQy6pgAiAQAAAA==.Batimo:BAAALgAECgQJBAAAAA==.Bayle:BAAALgADCgMJAwAAAA==.',
Be='Beamin:BAAALgADCgQJBAAAAA==.Beaversrock:BAAALgADCgcJEQAAAA==.Behp:BAAALgADCgcJBgAAAA==.Bellithia:BAABLgAECn8lAAMNAAkJPh73CQDIAgANAAkJPh73CQDIAgAOAAEJNQunhgAsAAAAAA==.Belyne:BAAALgAECgEJAQABLgAECgkJJQANAD4eAA==.',
Bi='Bielsebub:BAAALgADCgUJBQAAAA==.Biological:BAAALgAECgEJAQAAAA==.',
Bk='Bkdh:BAAALgAECgYJEAAAAA==.',
Bl='Blackmon:BAACLgAFFH8PAAIPAAQJ/QsWfAD/AAAPAAQJ/QsWfAD/AAAuAAQKfxUAAw8ACQkMF4RsAIUBAA8ACQkMF4RsAIUBABAABgl3Bxo+AI0AAAAA.Blitzkreig:BAAALgAECgYJCQAAAA==.Bløødy:BAAALgAECgEJAQABLgAECgUJBgAFAAAAAA==.',
Bo='Boomboombear:BAAALgAECgcJDQAAAA==.Boomya:BAABLgAECn8fAAIRAAgJ0hi2IAA5AgARAAgJ0hi2IAA5AgAAAA==.',
Br='Britneyspear:BAABLgAECn8mAAMSAAgJlRhXNQDUAQASAAcJ7BtXNQDUAQATAAUJZg9jMgD0AAAAAA==.Broken:BAAALgADCgMJBwAAAA==.',
Bu='Bubbulubb:BAABLgAECn8hAAIPAAkJXRfBRAAnAgAPAAkJXRfBRAAnAgAAAA==.Bullthing:BAACLgAFFH8FAAMDAAIJ1xtJMgCfAAADAAIJ1xtJMgCfAAAEAAEJuQEdvQAxAAAuAAQKfyoABAMACQnUIvUCAG8DAAMACQnUIvUCAG8DAAQABAkJFnffAM4AAAYAAQmLG5lCAE0AAAAA.',
Ca='Caladrial:BAAALgADCgMJAwAAAA==.Calex:BAABLgAECn81AAMUAAgJuSGvCwCeAgAUAAgJuSGvCwCeAgAVAAUJaiDWOgCWAQAAAA==.Cassyn:BAAALgAECgEJBAAAAA==.',
Ch='Chansey:BAABLgAECn8nAAINAAkJnB7fCACuAgANAAkJnB7fCACuAgAAAA==.Charged:BAAALgAECgMJBAAAAA==.Chesna:BAABLgAECn8sAAMWAAkJSx1ZCgCHAgAWAAkJSx1ZCgCHAgAXAAUJJwdaSQCzAAAAAA==.Chinchulin:BAAALgAECgQJAwAAAA==.Chipsbambee:BAABLgAECn8qAAILAAkJ4QztUQCiAQALAAkJ4QztUQCiAQAAAA==.Chttr:BAAALgAECgMJBAAAAA==.Chttrbox:BAACLgAFFH8lAAMYAAcJpyJkAQDxAQAYAAYJfiRkAQDxAQAVAAUJExO8KAAsAQAuAAQKfzQAAxgACQnbJbQCAOMCABgACAk7JrQCAOMCABUACQlGGcQiAA4CAAAA.',
Co='Combust:BAACLgAFFH8QAAICAAQJ6RkjRwBOAQACAAQJ6RkjRwBOAQAuAAQKf0MAAgIACQmgIkMOAAMDAAIACQmgIkMOAAMDAAAA.Corstar:BAAALgADCgUJBQAAAA==.',
Cr='Crigillin:BAAALgADCgMJAwAAAA==.Crux:BAAALgAECgQJCAAAAA==.',
Da='Dalexios:BAAALgADCgYJAQAAAA==.Dallan:BAAALgADCgcJCgAAAA==.Daniella:BAAALgADCgYJBgAAAA==.Danyy:BAAALgAECgEJAQAAAA==.Dao:BAACLgAFFH8IAAIVAAMJzBR5EwDDAAAVAAMJzBR5EwDDAAAuAAQKfxUAAxUACAnEHMISAIACABUACAnEHMISAIACABQABAl+BMt/AGIAAAAA.Darelina:BAAALgADCgYJDQAAAA==.Darkhelmet:BAAALgADCggJDAAAAA==.Darkwarspark:BAAALgADCgQJAwAAAA==.',
De='Deathvader:BAAALgADCgcJDAAAAA==.Delaomega:BAABLgAECn86AAMQAAkJvQpzJAAlAQAQAAkJvQpzJAAlAQAPAAEJjQahaAEuAAAAAA==.Derey:BAAALgADCgEJAgAAAA==.Devien:BAAALgADCgcJBwAAAA==.',
Di='Diber:BAAALgAECgMJAwAAAA==.Divinebovin:BAAALgADCgcJCAAAAA==.',
Dr='Drakvader:BAAALgAECgIJAwABLgAECgcJGwABABgMAA==.Drakvor:BAABLgAECn8uAAMQAAkJShXpCgBoAgAQAAkJShXpCgBoAgAPAAEJcQHlOwEbAAAAAA==.Drash:BAABLgAECn9HAAMZAAgJqhaYCQDaAQAZAAgJwRWYCQDaAQAQAAMJFBAuPwCJAAAAAA==.Drazgal:BAAALgADCgcJCQAAAA==.Dreni:BAAALgAECgEJAQAAAA==.Droni:BAAALgADCggJCAAAAA==.',
Du='Duhai:BAAALgAECgUJBAAAAA==.Dumbledore:BAABLgAECn8uAAIQAAkJfhsTDQAvAgAQAAkJfhsTDQAvAgAAAA==.Dumpnloads:BAAALgADCgEJAgAAAA==.Durotagg:BAAALgAFFAEJAQAAAA==.',
['Dí']='Dím:BAAALgAECgYJCAAAAA==.',
Ea='Eaterofholes:BAAALgAECgYJBwAAAA==.',
Ed='Edubijes:BAAALgAECgcJCgABLgAECggJHgASACkSAA==.',
Eg='Egres:BAAALgAECgYJCwAAAA==.',
El='Elemequation:BAAALgAECgEJBAAAAA==.Elfguy:BAAALgADCgcJEwAAAA==.',
En='Endléss:BAABLgAECn8rAAIMAAgJOhrdEwAFAgAMAAgJOhrdEwAFAgAAAA==.Envision:BAAALgADCgQJAwABLgAECgUJCAAFAAAAAA==.',
Er='Erbium:BAAALgAECgQJBQAAAA==.Eremetrii:BAEALgAFFAEJAQAAAA==.',
Es='Eshwyn:BAAALgAECgYJBgAAAA==.Esquandolas:BAAALgADCgcJGAAAAA==.',
Ev='Evotibs:BAABLgAECn8bAAMBAAcJGAwcGADlAAABAAcJGAwcGADlAAAMAAUJZQbZPgDGAAAAAA==.',
Fe='Fec:BAAALgAECgYJEQABLgAECgkJQAAaAHQfAA==.',
Fi='Fibaldrachi:BAABLgAECn8vAAIbAAkJ9SNuAQAOAwAbAAkJ9SNuAQAOAwAAAA==.',
Fr='Fragnarr:BAAALgADCgQJBAAAAA==.Frosting:BAACLgAFFH8JAAICAAMJIxCjegDeAAACAAMJIxCjegDeAAAuAAQKfykAAgIACAmaIEYgAJgCAAIACAmaIEYgAJgCAAAA.',
Ga='Galaxy:BAAALgADCgMJBQAAAA==.',
Gh='Ghantu:BAABLgAECn8bAAIUAAgJkh1WGgADAgAUAAgJkh1WGgADAgAAAA==.Ghiro:BAAALgAECgEJAQAAAA==.Ghunk:BAAALgADCgYJBgAAAA==.',
Go='Goldennight:BAAALgADCgYJCQAAAA==.Gornathia:BAAALgAECgcJDQAAAA==.',
Gr='Gradeabeef:BAAALgAECgUJBQAAAA==.Grandall:BAAALgAECgEJAwAAAA==.Grimsteel:BAAALgAECgMJAwAAAA==.Gruon:BAABLgAECn9CAAIcAAgJRg8ELABqAQAcAAgJRg8ELABqAQAAAA==.',
Gu='Gulzan:BAACLgAFFH8GAAIUAAMJTwqxNACwAAAUAAMJTwqxNACwAAAuAAQKfyUAAhQACAkUFlIfANwBABQACAkUFlIfANwBAAAA.',
['Gø']='Gøkû:BAAALgAECgYJDgAAAA==.',
Ha='Hacks:BAABLgAECn8lAAIaAAkJjBJbEwCuAQAaAAkJjBJbEwCuAQAAAA==.Haymakerxd:BAABLgAECn8aAAIPAAgJxiMDCgAaAwAPAAgJxiMDCgAaAwAAAA==.',
He='Healtastic:BAAALgADCgcJBwAAAA==.Heealzz:BAAALgAECgYJDQAAAA==.Helendir:BAAALgAECgIJAgAAAA==.',
Hu='Huntsagee:BAAALgADCgUJCAAAAA==.',
Hy='Hyacinthe:BAABLgAECn8tAAQHAAkJ9RvgAwBQAgAHAAkJ9RvgAwBQAgAIAAQJ3BHfHwCiAAAKAAMJCgyV3gCVAAAAAA==.Hypernova:BAAALgAECgUJBQAAAA==.',
Ib='Ibogaine:BAAALgADCgIJAgAAAA==.',
Ic='Iceshep:BAAALgAFFAEJAQAAAA==.',
Id='Iden:BAAALgAECgYJCQAAAA==.Idtrapthát:BAAALgADCgMJAwAAAA==.',
Il='Illidanswife:BAAALgAECgYJDAAAAA==.Iluvatar:BAAALgADCgQJBAAAAA==.',
Im='Immamageboi:BAABLgAECn8nAAICAAgJHwjMlwBFAQACAAgJHwjMlwBFAQAAAA==.',
In='Infernal:BAAALgAECgcJCgAAAA==.Ingo:BAAALgADCgkJDgAAAA==.Inspiremoon:BAABLgAECn8VAAILAAcJ4RI8bQBcAQALAAcJ4RI8bQBcAQAAAA==.Interror:BAAALgAECgYJDgAAAA==.',
Ip='Ipak:BAAALgADCgEJAQAAAA==.',
Ir='Iranos:BAABLgAECn8nAAMEAAgJqiAaJABrAgAEAAgJqiAaJABrAgAGAAIJLgwzPwBYAAAAAA==.Irishpryde:BAAALgAECgEJAQAAAA==.',
Ja='Jackiechanda:BAAALgAECgQJCQAAAA==.Jaraxxus:BAAALgAECgUJCQABLgAECgYJDQAFAAAAAA==.',
Je='Jelipa:BAAALgADCgEJAQABLgAECggJHgASACkSAA==.',
Jo='Johnnylaw:BAAALgAECgMJAwAAAA==.Joshns:BAAALgADCgEJAQAAAA==.',
Ka='Kaellyn:BAAALgAECgcJCgAAAA==.Kaicelius:BAAALgAECgMJAwAAAA==.Kaimari:BAAALgADCgcJBwAAAA==.Kaloesh:BAAALgADCgQJBAABLgAFFAEJAQAFAAAAAA==.Kanakana:BAABLgAECn8nAAIVAAgJlR9KFgCNAgAVAAgJlR9KFgCNAgAAAA==.',
Ke='Kendana:BAAALgADCgYJDgAAAA==.Keyadron:BAAALgAECgUJCAAAAA==.',
Ki='Kindly:BAAALgAECgEJAgAAAA==.Kirab:BAABLgAECn8XAAIGAAgJoAW0MACYAAAGAAgJoAW0MACYAAAAAA==.Kirinmor:BAAALgADCggJCAAAAA==.Kis:BAAALgAECgUJBwAAAA==.Kisten:BAABLgAECn8XAAIKAAgJhQMRsQDeAAAKAAgJhQMRsQDeAAAAAA==.',
Ko='Kogorn:BAAALgADCgIJAgAAAA==.Korja:BAAALgAECgEJAQAAAA==.Kosmos:BAAALgAECgcJEAABLgAFFAMJAwAFAAAAAA==.',
Kr='Kreid:BAABLgAECn8cAAIXAAgJKRtcEwByAgAXAAgJKRtcEwByAgAAAA==.Kreìd:BAAALgADCgEJAQABLgAECggJHAAXACkbAA==.',
Ku='Kungfoupanda:BAAALgAECgIJAwAAAA==.',
Ky='Kyrr:BAAALgAFFAQJBAAAAA==.',
La='Larbear:BAAALgADCgIJAgAAAA==.Larrysham:BAAALgADCgEJAQAAAA==.',
Le='Lemén:BAABLgAECn8sAAIdAAkJoBUQMgD0AQAdAAkJoBUQMgD0AQAAAA==.Lenore:BAAALgAECgMJAwAAAA==.',
Li='Lierax:BAABLgAECn8tAAMeAAkJTh5eDQCCAgAeAAkJTh5eDQCCAgAfAAUJHBTxIQAbAQAAAA==.Lightpheonix:BAAALgADCgUJBQAAAA==.Ligmaw:BAAALgAECgQJCwAAAA==.Lildonny:BAAALgAECgEJAgAAAA==.Lilia:BAAALgAFFAcJBAAAAA==.Lilrobo:BAAALgADCgcJDQAAAA==.Linaei:BAABLgAECn8xAAIOAAkJSRD+HQDNAQAOAAkJSRD+HQDNAQAAAA==.Linestia:BAAALgAECgEJAgABLgAECgYJCwAFAAAAAA==.Littlewingz:BAABLgAECn8tAAIgAAkJUCQUAQCdAwAgAAkJUCQUAQCdAwAAAA==.',
Lo='Lobotomy:BAABLgAFFH8HAAISAAQJogwAJAAXAQASAAQJogwAJAAXAQAAAA==.Lockinflame:BAACLgAFFH8IAAIKAAQJ4xrRMQBpAQAKAAQJ4xrRMQBpAQAuAAQKfxUAAgoACAn4IHoXAJICAAoACAn4IHoXAJICAAAA.Lockinload:BAAALgAFFAMJAwAAAA==.Loka:BAAALgAECgEJAQAAAA==.',
['Lá']='Lálatina:BAAALgAECgMJAwAAAA==.',
Ma='Magnataur:BAAALgADCgQJBQAAAA==.Mahdek:BAAALgAECgMJBAABLgAECgUJBgAFAAAAAA==.Maladreks:BAAALgAECgEJAQAAAA==.Malsandre:BAAALgADCgUJBQABLgAECgkJLQAHAPUbAA==.Mascro:BAAALgADCgIJAgAAAA==.Maverrus:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Mawz:BAABLgAECn8aAAIYAAgJ2hyGCwDwAQAYAAgJ2hyGCwDwAQAAAA==.Mayormcçhees:BAAALgADCgMJAwAAAA==.',
Me='Mecat:BAACLgAFFH8JAAIRAAIJQyJqOQDEAAARAAIJQyJqOQDEAAAuAAQKfyEAAhEACQnrImMJAPwCABEACQnrImMJAPwCAAAA.Meedlefinger:BAAALgAECgQJBQAAAA==.Megatonne:BAAALgADCgkJCQAAAA==.Melathia:BAABLgAECn8eAAIKAAkJQQmSdABLAQAKAAkJQQmSdABLAQAAAA==.Meliza:BAAALgAECgQJBwAAAA==.Melløw:BAAALgAECgEJAgAAAA==.',
Mo='Mommyshere:BAAALgADCgEJAQAAAA==.Monilara:BAAALgAECgQJBQAAAA==.Morman:BAAALgAECgkJCAAAAA==.',
Mu='Musclebear:BAACLgAFFH8JAAIhAAQJmQk9IAAPAQAhAAQJmQk9IAAPAQAuAAQKfxgAAiEACAkJF1kZAMIBACEACAkJF1kZAMIBAAAA.',
My='Mythaux:BAAALgADCgMJAwABLgAFFAEJAQAFAAAAAA==.',
['Mâ']='Mâk:BAAALgADCggJCAAAAA==.',
Na='Napalm:BAAALgAECgUJBQABLgAECgkJLgACAIYcAA==.Nashamadd:BAAALgADCgIJAgAAAA==.',
Ne='Neero:BAABLgAECn8kAAIdAAgJGxujKgAUAgAdAAgJGxujKgAUAgAAAA==.Nelena:BAABLgAECn9AAAIVAAgJOQo9VwBLAQAVAAgJOQo9VwBLAQAAAA==.Nenyve:BAAALgADCgQJBQAAAA==.Nerodrachen:BAAALgADCgMJAwAAAA==.Newgrim:BAAALgADCgMJAwAAAA==.Newurt:BAAALgAECgQJDAAAAA==.Nezhyt:BAABLgAECn8qAAMIAAgJ4B7oAwA9AgAIAAgJKh7oAwA9AgAHAAUJeh7FFAAXAQABLgAFFAEJAQAFAAAAAA==.',
Ni='Nicolbolas:BAABLgAECn8iAAMeAAkJNRYGGwD2AQAeAAkJNRYGGwD2AQAgAAIJewIVRQBHAAAAAA==.Nightshow:BAAALgADCgUJBQAAAA==.',
No='Nori:BAACLgAFFH8NAAIYAAQJCiboAQDGAQAYAAQJCiboAQDGAQAuAAQKfxkAAhgABwnrJdYEAJUCABgABwnrJdYEAJUCAAEuAAUUCAkvAAIAUiQA.Notdragon:BAAALgADCgMJBQAAAA==.Notorious:BAABLgAECn8jAAMgAAkJgRaEBwB4AgAgAAkJgRaEBwB4AgAeAAMJYRB7ZQCcAAAAAA==.',
Nt='Ntaicen:BAAALgADCgMJAwAAAA==.',
Os='Osiris:BAAALgADCgYJBgAAAA==.',
Pa='Pandalin:BAAALgAECgUJBgAAAA==.Pap:BAAALgADCgYJCAAAAA==.Papavodou:BAAALgADCgQJBAAAAA==.Paýp:BAABLgAECn8zAAQeAAkJIhX9FAArAgAeAAkJIhX9FAArAgAgAAgJdwOvHgD6AAAfAAIJPxIeGgBzAAAAAA==.',
Pe='Pelgryn:BAAALgADCgYJCwAAAA==.Pentasaurusr:BAABLgAECn8eAAMKAAcJSh+bQAAMAgAKAAYJSh+bQAAMAgAIAAIJ6BkiTACJAAAAAA==.',
Pl='Platemedic:BAAALgAECgYJBwAAAA==.',
Po='Polevik:BAAALgAFFAEJAQAAAA==.Pookkee:BAAALgAECgYJCwAAAA==.Porkahantas:BAAALgAECgYJEwAAAA==.Portgasdace:BAAALgAECgEJAwAAAA==.',
Pp='Ppat:BAAALgAECgYJEQAAAA==.',
Py='Pyromainiac:BAAALgADCgEJAQAAAA==.',
Qu='Queteimporta:BAABLgAECn8eAAQSAAgJKRK4RQAmAQASAAcJuwy4RQAmAQAaAAQJZBN/KwDRAAATAAQJ0gtvXgBZAAAAAA==.',
Ra='Ratamahatta:BAAALgAECgMJAwAAAA==.Rayeona:BAAALgAECgYJDAAAAA==.',
Re='Recheals:BAAALgAECgkJCgAAAA==.Recmod:BAABLgAECn8dAAMhAAcJ+BiCJABlAQAhAAcJ+BiCJABlAQAiAAEJSxGBIwA/AAABLgAECgkJCgAFAAAAAA==.Recsdru:BAAALgADCgkJDgABLgAECgkJCgAFAAAAAA==.Rendover:BAAALgAECgYJBwAAAA==.Return:BAABLgAECn9AAAIaAAkJdB/kBQDXAgAaAAkJdB/kBQDXAgAAAA==.Reze:BAAALgAECgYJBwAAAA==.',
Rh='Rhimeholt:BAABLgAECn8gAAMXAAkJ7hpPEQCGAgAXAAkJ7hpPEQCGAgAjAAEJgQqVmQAtAAAAAA==.',
Ri='Rikoria:BAAALgAECgYJDQAAAA==.',
Ro='Roussalina:BAAALgAECgEJBAAAAA==.Roxagar:BAAALgAECgQJBgABLgAECgcJGwABABgMAA==.',
Ry='Ryahask:BAABLgAECn8vAAIYAAkJwxHEDADZAQAYAAkJwxHEDADZAQAAAA==.',
['Rä']='Rädagast:BAAALgADCgIJAgAAAA==.',
Sa='Sadisticrage:BAACLgAFFH8FAAIEAAIJVxCwiACLAAAEAAIJVxCwiACLAAAuAAQKf0MAAgQACQmtH6wTAMQCAAQACQmtH6wTAMQCAAAA.Sae:BAAALgAECgMJAwAAAA==.Sammyshoes:BAAALgAECggJDwAAAA==.Sanguine:BAAALgAECgYJCgAAAA==.',
Sc='Scottklam:BAAALgAECgYJCgAAAA==.Scrimbo:BAAALgAECgQJBQAAAA==.',
Se='Seaturtles:BAAALgADCgYJBgAAAA==.Seeturtle:BAABLgAECn8lAAMkAAkJ9B4KAwD4AQAkAAcJZyEKAwD4AQACAAgJLBp1aACmAQAAAA==.Sellassie:BAAALgADCgYJDwAAAA==.Selvala:BAAALgAECgEJAgAAAA==.Selyste:BAAALgAECgQJBQAAAA==.Selûne:BAAALgAECgIJAgAAAA==.Senthara:BAAALgAECggJEgAAAA==.',
Sh='Shadow:BAABLgAECn8bAAIPAAgJjhKPWwCuAQAPAAgJjhKPWwCuAQAAAA==.Shanaa:BAAALgAECgEJAQAAAA==.Shera:BAAALgADCgYJCwAAAA==.Shooter:BAAALgAECgEJAQAAAA==.Shxggy:BAAALgAECgEJAQAAAA==.',
Sk='Skull:BAAALgAECgEJAQAAAA==.',
Sl='Slagathor:BAAALgAECgMJBAAAAA==.Slippie:BAAALgAECgMJAwAAAA==.Slipstreamer:BAAALgADCgEJAQAAAA==.',
Sm='Smell:BAABLgAECn9EAAIEAAkJkhn+MAAyAgAEAAkJkhn+MAAyAgAAAA==.',
So='Solheim:BAACLgAFFH8LAAIEAAMJ7SHZPAAkAQAEAAMJ7SHZPAAkAQAuAAQKfxYAAgQACAlTJZETAMUCAAQACAlTJZETAMUCAAAA.',
Sp='Spacemonk:BAAALgAECgQJCAAAAA==.Spire:BAAALgAFFAIJAgAAAA==.Sproutling:BAABLgAECn8sAAMRAAkJkQlfTQBQAQARAAkJkQlfTQBQAQAcAAcJmgWSTQDJAAAAAA==.',
St='Stearphen:BAABLgAECn8VAAMaAAkJYBXPEgC1AQAaAAkJYBXPEgC1AQASAAEJ5wOhsAAqAAAAAA==.Steze:BAAALgAECgEJAQAAAA==.Stormy:BAAALgADCgEJAQAAAA==.Stumpi:BAAALgAECgcJDwAAAA==.',
Sw='Swazti:BAABLgAECn8eAAIKAAgJUxLKWQCLAQAKAAgJUxLKWQCLAQAAAA==.',
Ta='Tashir:BAAALgADCgcJBwABLgAECgkJCAAFAAAAAA==.Taurnil:BAACLgAFFH8JAAIHAAIJpQuADgCWAAAHAAIJpQuADgCWAAAuAAQKf0QAAgcACAmSG4UGAAUCAAcACAmSG4UGAAUCAAAA.',
Te='Teledor:BAAALgAECgQJBgAAAA==.Teloiv:BAAALgADCggJBwAAAA==.Telperion:BAAALgADCgYJBgAAAA==.',
Th='Thadontrump:BAAALgAECgMJBAAAAA==.',
Ti='Tibidari:BAAALgAECgEJAQABLgAECgcJGwABABgMAA==.Timika:BAABLgAECn8/AAMlAAkJoxk3GQD2AQAlAAgJCxg3GQD2AQANAAcJGBYkGwDpAQAAAA==.Tinysunn:BAAALgADCgYJBgAAAA==.',
To='Topharius:BAAALgADCgIJAgAAAA==.Toscc:BAAALgAECgMJBAAAAA==.',
Tr='Trales:BAAALgAECgYJBgAAAA==.',
Ty='Typeshift:BAABLgAFFH8QAAImAAUJlh9PBwBrAQAmAAUJlh9PBwBrAQAAAA==.',
Uc='Uchtdwarf:BAAALgAECgQJBAAAAA==.',
Ue='Uen:BAAALgAECgQJBwABLgAFFAcJHAAeALoWAA==.',
Uk='Ukan:BAAALgADCgQJAwAAAA==.',
Ux='Uxx:BAABLgAECn8VAAIPAAYJ2RW0iQBJAQAPAAYJ2RW0iQBJAQAAAA==.',
Va='Vaeron:BAABLgAECn8VAAIhAAcJ3htJGADNAQAhAAcJ3htJGADNAQAAAA==.',
Ve='Veckna:BAAALgADCgEJAQAAAA==.Velithria:BAAALgADCgUJBQAAAA==.Vengeancez:BAABLgAECn8oAAISAAkJuBFMJwC6AQASAAkJuBFMJwC6AQAAAA==.Venomsecho:BAABLgAECn8jAAInAAkJ2BQYDgDFAQAnAAkJ2BQYDgDFAQAAAA==.Venomshexo:BAAALgAECgEJAQAAAA==.Verboux:BAAALgAECgIJBAAAAA==.Versacé:BAAALgADCgEJAQAAAA==.',
Vi='Vicodin:BAAALgAECgEJAwAAAA==.Videl:BAAALgAECgEJAQAAAA==.Visionaries:BAAALgAECgUJCAAAAA==.',
Vo='Voldemort:BAAALgADCgcJBwAAAA==.Vorrixa:BAAALgAECggJEQAAAA==.',
We='Weathergirl:BAAALgAECgkJEwAAAA==.',
Wh='Whisky:BAAALgAECgYJCQAAAA==.',
Wi='Winniethefu:BAABLgAECn8jAAIXAAgJ0BiZFwADAgAXAAgJ0BiZFwADAgAAAA==.Wisps:BAAALgADCgEJAQABLgAECgYJBgAFAAAAAA==.',
Wo='Wolffire:BAAALgAECgMJAgABLgAECgQJCAAFAAAAAA==.Worshipme:BAAALgAECgYJBgAAAA==.',
Wy='Wy:BAAALgAECgYJEAAAAA==.',
Xa='Xanna:BAAALgAFFAIJAgAAAA==.',
Xy='Xylith:BAACLgAFFH8GAAIGAAMJGhP4AwCeAAAGAAMJGhP4AwCeAAAuAAQKfycAAgYACAmlItwCAPsCAAYACAmlItwCAPsCAAAA.',
Ye='Yellowman:BAAALgADCgYJBgAAAA==.',
Yu='Yungdon:BAAALgADCggJCAAAAA==.Yunàlestrà:BAACLgAFFH8FAAMKAAUJrwMTcgDRAAAKAAQJrwMTcgDRAAAIAAEJAABsKwAAAAAuAAQKfxsAAwoACQlCDj9KALYBAAoACQlCDj9KALYBAAgAAQmYB5B2AC4AAAAA.',
Za='Zach:BAABLgAECn8uAAICAAkJhhx4HwCbAgACAAkJhhx4HwCbAgAAAA==.',
Zm='Zmagez:BAAALgAECggJEgAAAA==.',
Zy='Zylith:BAAALgAECgQJBQAAAA==.',
['Äv']='Ävatar:BAABLgAECn8UAAIXAAcJiwVaPADzAAAXAAcJiwVaPADzAAAAAA==.',
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
