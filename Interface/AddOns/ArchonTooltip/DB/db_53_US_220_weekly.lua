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

local lookup = {'Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','DemonHunter-Havoc','Monk-Mistweaver','Druid-Balance','Mage-Frost','Mage-Arcane','Warrior-Protection','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warrior-Fury','Evoker-Preservation','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Shaman-Enhancement','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Arms','DemonHunter-Devourer','DeathKnight-Frost','Druid-Feral','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Holy','Priest-Discipline','Rogue-Outlaw','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Druid-Guardian','Druid-Restoration','Hunter-Survival',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaragon:BAAANQAECggIEAABNQAFFAkJGgABAAAdAA==.',
Ab='Abysmal:BAABNQAECn8aAAMCAAYKHBJBjwBfAQACAAYKHBJBjwBfAQADAAEKAACLQwEqAAAAAA==.',
Ad='Adame:BAAANQAECgEIAQAAAA==.Adjudicator:BAAANQAECgQIBAABNQAECgQIBQAEAAAAAA==.',
Ae='Aeriona:BAABNQAECn8pAAIFAAgK7R1NTACsAgAFAAgK7R1NTACsAgAAAA==.Aerobear:BAAANQADCgYIBgABNQAECgkJHAAGAI0SAA==.Aerolock:BAAANQAECgUICwABNQAECgkJHAAGAI0SAA==.Aerosong:BAABNQAECn8cAAIGAAkKjRJmMAAgAgAGAAkKjRJmMAAgAgAAAA==.',
Af='Affalon:BAAANQAECgQICAAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Aine:BAAANQAECggIEAAAAA==.Ainkor:BAAANQAECgYICAABNQAFFAEIAQAEAAAAAA==.',
Ak='Akyospirit:BAABNQAECn8sAAICAAgKsQ4TdwCiAQACAAgKsQ4TdwCiAQAAAA==.',
Al='Alchemised:BAAANQAECggIDwABNQAECggIGAAHAOodAA==.Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAABNQAECn8bAAIIAAUK1gq6dwDnAAAIAAUK1gq6dwDnAAAAAA==.Allumin:BAAANQADCggIFAAAAA==.Alpha:BAABNQAECn8pAAMJAAgKrhh3CABVAgAJAAgKQBh3CABVAgAKAAgKeRVbrQAmAgAAAA==.',
Am='Amamonk:BAABNQAECn8WAAIBAAgK/RW8IQAYAgABAAgK/RW8IQAYAgAAAA==.Ammert:BAAANQAECgQIBAAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAcIFwALADMWAA==.Angliko:BAAANQADCgMJAwABNQAECggIJgAMAB4aAA==.Annei:BAABNQAECn8wAAMNAAkKCyE+EgA2AwANAAgKIiM+EgA2AwAOAAYKoBLoOgBOAQABNQAFFAEIAQAEAAAAAA==.Anomandaris:BAAANQAECgYIEAAAAA==.Anquan:BAAANQAECgQIEAAAAA==.Anya:BAABNQAECn8YAAIPAAgKchNSFQA4AgAPAAgKchNSFQA4AgAAAA==.',
Ap='Apedemak:BAAANQAECgEIAQAAAA==.Apothica:BAABNQAECn8dAAIKAAcKIw1F9QCeAQAKAAcKIw1F9QCeAQAAAA==.Apothicc:BAAANQAECgUICQABNQAECgcIHQAKACMNAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUJDAAAAA==.',
Aq='Aquae:BAAANQAECgYICAABNQAECgcIGAAQABMcAA==.',
Ar='Arcohunt:BAAANQADCgcJBwABNQAECgUJDAAEAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAAANQAECggIEwAAAA==.Argonaut:BAAANQADCggICAAAAA==.',
As='Asheritâ:BAAANQAECgUIDgAAAA==.Ashvalis:BAABNQAECn8ZAAIRAAYKBCJQFgBQAgARAAYKBCJQFgBQAgAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECgYIDgAAAA==.Askr:BAAANQAECgUICgAAAA==.Asphar:BAABNQAECn8aAAISAAgKJCI3JwD5AgASAAgKJCI3JwD5AgAAAA==.Astria:BAAANQADCgUIBQAAAA==.Asynic:BAAANQADCgYIEAABNQAECgUIDQAEAAAAAA==.',
Au='Aung:BAABNQAECn84AAIGAAgKiyVfCQBnAwAGAAgKiyVfCQBnAwAAAA==.Auri:BAAANQAECgEIAQAAAA==.',
Av='Avitarkorra:BAAANQAECgQICAAAAA==.',
Ax='Axex:BAAANQAECgcIEgAAAA==.',
Az='Azamii:BAABNQAECn8hAAMCAAgKBBxJVgALAgACAAcKgxpJVgALAgADAAQKdhvKvAAUAQABNQAECgkJKwANAD4eAA==.Azarion:BAABNQAECn8hAAMTAAkKvROiJgBAAQAUAAcKtA25kAC4AQATAAUKlBKiJgBAAQAAAA==.Azill:BAACNQAFFH8MAAIBAAUKpxMZBwCDAQABAAUKpxMZBwCDAQA1AAQKfyQAAgEACQpkHxERANYCAAEACQpkHxERANYCAAAA.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAwAAAA==.Azurefury:BAABNQAECn8dAAIVAAcKBwiGHQCEAQAVAAcKBwiGHQCEAQAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Bandi:BAABNQAECn8cAAIUAAgKYxUGWABKAgAUAAgKYxUGWABKAgAAAA==.Bartrak:BAAANQADCgIJAgABNQAECgIIAwAEAAAAAA==.Battôsai:BAAANQAECgQIDAAAAA==.',
Be='Bearfucius:BAABNQAECn8eAAMBAAcK1hbUJQDxAQABAAcK1hbUJQDxAQAHAAUKhw1iMADiAAAAAA==.Bearrific:BAABNQAECn8XAAMPAAcK9BB5IgCzAQAPAAcK9BB5IgCzAQAWAAEKXwVDowAuAAAAAA==.Behomadra:BAAANQAECgYIBgAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAABNQAECn8ZAAMXAAkKIyGYDwAvAwAXAAkKIyGYDwAvAwAYAAEKzgH/+gAaAAAAAA==.Beyond:BAAANQAECgQIBAAAAA==.',
Bi='Billthekid:BAAANQADCgcIBwAAAA==.Binksy:BAACNQAFFH8GAAIZAAIKzxWOLACUAAAZAAIKzxWOLACUAAA1AAQKfzUAAhkACQoLH383AOMCABkACQoLH383AOMCAAAA.Biscuit:BAACNQAFFH8XAAMLAAcKMxY+AQDfAQALAAYKhBs+AQDfAQAZAAEK7gBIOwBJAAA1AAQKfzcAAwsACQoFJg4BAMkDAAsACQrBJQ4BAMkDABkABQrFG2i4AIoBAAAA.',
Bl='Blaam:BAAANQAECgEIAgAAAA==.Blazin:BAACNQAFFH8PAAMKAAUKQw9BHgCLAQAKAAUKswtBHgCLAQAJAAEKnBApEwBHAAA1AAQKfysAAwoACQpfIUdFAPkCAAoACQrjIEdFAPkCAAkABQpqG3MTAG8BAAAA.Blinkzy:BAAANQADCgUICQABNQAFFAIIBgAZAM8VAA==.Blitzoria:BAAANQADCgYIBgABNQAECgcIDgAEAAAAAA==.Bloui:BAAANQADCgYIFwAAAA==.Blueknight:BAABNQAECn8eAAMXAAcKlQaocQArAQAXAAcKlQaocQArAQAYAAIKUAZbywBSAAAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgMIBgAAAA==.Bonythumper:BAAANQADCgQIBAAAAA==.Borlok:BAAANQAECgcIIwAAAQ==.',
Br='Brannigan:BAABNQAECn8vAAIZAAkK2CB1IQAxAwAZAAkK2CB1IQAxAwAAAA==.Brannigandh:BAABNQAECn8hAAQMAAgKoRjmCgAjAgAMAAgKfBjmCgAjAgAaAAYKvQ28PwBIAQAGAAEKAAASjAA/AAABNQAECgkJLwAZANggAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIDAAAAA==.Briantu:BAAANQADCggJCAAAAA==.Brickfelt:BAAANQABCgYICgAAAA==.Brickitphil:BAABNQAECn8bAAIbAAkK5B6LEQD/AgAbAAkK5B6LEQD/AgAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIIAgAEAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAABNQAECn8YAAMQAAcKExx5CgAfAgAQAAYK5x15CgAfAgAZAAMK4QsWIwGLAAAAAA==.Bulldan:BAAANQAECgQIBAAAAA==.Bullvi:BAAANQAECgQIBgAAAA==.',
['Bä']='Bärkler:BAAANQAECgUJBgAAAA==.',
['Bé']='Béckléy:BAABNQAECn8XAAIcAAkKiCGwBAA6AwAcAAkKiCGwBAA6AwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cannïbal:BAAANQAECgUICQAAAA==.Cara:BAAANQADCgMIBAAAAA==.Carra:BAABNQAECn8nAAISAAgKYBjVWgBhAgASAAgKYBjVWgBhAgAAAA==.Cassiopeía:BAEANQAECgQIBQABNQAECggICAAEAAAAAA==.Catriona:BAABNQAECn8hAAISAAYK2gnRxwBtAQASAAYK2gnRxwBtAQAAAA==.',
Ch='Charcuterie:BAACNQAFFH8XAAIdAAcKMQ+nAQD5AQAdAAcKMQ+nAQD5AQA1AAQKfx4AAh0ACQrrH7gGANoCAB0ACQrrH7gGANoCAAAA.Chartou:BAAANQADCggICAAAAA==.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheeze:BAAANQABCgUIBQABNQAECgcIGwAeAOULAA==.Cheezeburg:BAABNQAECn8bAAMeAAcK5QuhRQAnAQASAAYKkQ33twCPAQAeAAYKpQmhRQAnAQAAAA==.Chicken:BAAANQAECgcICAABNQAFFAcIFwALADMWAA==.Chikindalf:BAAANQADCgEJAQAAAA==.Chillidán:BAABNQAECn8kAAIaAAgKxwNgPwBLAQAaAAgKxwNgPwBLAQAAAA==.Choggie:BAABNQAECn8mAAMfAAkKFhSqSgA7AgAfAAkKFhSqSgA7AgAFAAYKawPaMwHGAAAAAA==.Chulainn:BAAANQAECgYIDAAAAA==.',
Co='Cons:BAABNQAECn8tAAMNAAkKzyDMFQAhAwANAAkKzyDMFQAhAwAgAAEKBAtxKgAuAAAAAA==.Corellon:BAABNQAECn8jAAISAAgKTx8ZLwDeAgASAAgKTx8ZLwDeAgAAAA==.',
Cr='Cranee:BAABNQAECn9GAAMUAAkKPBXcSAB1AgAUAAkKPBXcSAB1AgATAAIKqQLJaQBMAAAAAA==.Cranium:BAABNQAECn8VAAIbAAgKayEvGQC+AgAbAAgKayEvGQC+AgAAAA==.Crazytasty:BAABNQAECn8tAAISAAgK0iLnHAAjAwASAAgK0iLnHAAjAwAAAA==.Critcomander:BAAANQADCgYIDAAAAA==.',
Da='Dabora:BAABNQAECn80AAMWAAkKyyHrBQBxAwAWAAkKyyHrBQBxAwAhAAIKEg7/FwBhAAAAAA==.Damassan:BAAANQABCgYIBgAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECggIGgASAC0IAA==.Darige:BAAANQAECgUIDwAAAA==.Darim:BAABNQAECn8rAAIFAAkK1yRNCQCxAwAFAAkK1yRNCQCxAwABNQADCgYIBgAEAAAAAA==.Darthspawn:BAAANQAECgUIEgAAAA==.Daryn:BAAANQAECgEIAQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIIAgAEAAAAAA==.',
De='Deadchops:BAAANQAECgQIBQABNQAECgUIBgAEAAAAAA==.Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQAFFAEIAQAAAA==.Demonicfury:BAAANQAECgIIAgAAAA==.Dencity:BAABNQAECn8zAAMNAAkKTB01KADGAgANAAkKTB01KADGAgAgAAEK3wP+LwAjAAAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQAECgMIAwABNQAECggIJQAfAOsdAA==.Devitodevour:BAABNQAECn8tAAMUAAgKgBwkhQDVAQAUAAYK2BokhQDVAQATAAIK0B/QQgC4AAAAAA==.Devwarr:BAAANQAECgYIEgABNQAECggIJQAfAOsdAA==.Dezard:BAAANQABCgIIAgAAAA==.',
Dh='Dhbert:BAAANQAECgIIAgAAAA==.Dhomeli:BAAANQAECgIIAwAAAA==.Dhometri:BAAANQADCgIIAgAAAA==.',
Di='Dirtchez:BAAANQAECgUIBQAAAA==.Disastrophy:BAAANQAECgUIBgAAAA==.Disturbed:BAABNQAECn8wAAQUAAkKdxjPRwB4AgAUAAgKBhfPRwB4AgATAAMKIxbiOADcAAAiAAEKkwQjNAAoAAAAAA==.',
Dk='Dkson:BAACNQAFFH8NAAIXAAUK/xoKCwChAQAXAAUK/xoKCwChAQA1AAQKfy0AAhcACQrjIQUIAHwDABcACQrjIQUIAHwDAAAA.',
Do='Docen:BAAANQAECgQIBwAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.Download:BAAANQADCggICAAAAA==.',
Dr='Dragonfist:BAAANQAECgUICQAAAA==.Dragthyr:BAAANQADCgYIEgAAAA==.Druiaier:BAAANQAECgUIBwAAAA==.Druknatsu:BAAANQAECgUICgAAAA==.',
Du='Dustyknight:BAAANQAECgYIDQAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgcIEAAAAA==.',
Ec='Ecthan:BAAANQADCgQIBAAAAA==.',
Ed='Edge:BAABNQAECn8cAAICAAcKqx+LOwBvAgACAAcKqx+LOwBvAgAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elicio:BAAANQADCgMIAwAAAA==.Elidoria:BAEBNQAECn8uAAIKAAkKBRmXYQC7AgAKAAkKBRmXYQC7AgAAAA==.Elphinia:BAAANQADCgYJBgABNQAECgkJLAADAJAbAA==.',
En='Enoki:BAABNQAECn8YAAMDAAkK1x3qIgD6AgADAAkK1x3qIgD6AgACAAIKhwuv9wB2AAABNQAFFAcIFQAfAOoSAA==.',
Ep='Ephodess:BAAANQAECgUICAAAAA==.',
Er='Eraduckated:BAABNQAECn8aAAMWAAgKRx+/IAB5AgAWAAcKRx+/IAB5AgAhAAUKNhE4EAAbAQAAAA==.Erde:BAAANQAECgIIAgAAAA==.',
Es='Esco:BAAANQAECgEIAQAAAA==.Esile:BAABNQAECn8lAAIjAAcK6Qq1HQByAQAjAAcK6Qq1HQByAQAAAA==.Esoryn:BAABNQAECn8pAAIFAAgKmySnIAA/AwAFAAgKmySnIAA/AwAAAA==.',
Ev='Everlife:BAAANQAECgEIBQAAAA==.Evilainkor:BAABNQAECn8bAAIXAAkKlBkjJgCJAgAXAAkKlBkjJgCJAgABNQAFFAEIAQAEAAAAAA==.',
Ex='Exia:BAACNQAFFH8RAAIZAAYKFxKJDADjAQAZAAYKFxKJDADjAQA1AAQKfxkAAhkACQoiEqR3ACwCABkACQoiEqR3ACwCAAAA.',
Fa='Fauzzie:BAAANQAECgUIDgAAAA==.Fayrel:BAABNQAECn8aAAIDAAcKJApVlABtAQADAAcKJApVlABtAQAAAA==.',
Fe='Fedders:BAABNQAECn8rAAIFAAkKxiV2BADVAwAFAAkKxiV2BADVAwAAAA==.Felaids:BAABNQAECn8sAAQUAAgKIx81VwBNAgAUAAcKeh81VwBNAgATAAIKTRjrTgCRAAAiAAIKWhB3IgBmAAAAAA==.Felnyx:BAAANQADCgYJCgAAAA==.Felstone:BAAANQABCgIIAgABNQADCgYIBgAEAAAAAA==.Feor:BAAANQAECgYIDgAAAA==.Feralyn:BAAANQADCgYJCgAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAACNQAFFH8NAAIFAAQKhyAbDwBTAQAFAAQKhyAbDwBTAQA1AAQKfyIAAgUACQriIR03APACAAUACQriIR03APACAAAA.Fionas:BAAANQAECgUIDAAAAA==.Firexcracker:BAAANQAECgEIAQAAAA==.Fishfood:BAABNQAECn8oAAIYAAgKjhu3LQB5AgAYAAgKjhu3LQB5AgAAAA==.Fixer:BAAANQAECgEIAQAAAA==.',
Fl='Flappysnail:BAAANQADCgYICwAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fo='Foondin:BAAANQAECgQIBAAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frazzle:BAAANQADCgMIAwABNQAECgQIBAAEAAAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAABNQAECn8hAAIKAAkKahRbiQBsAgAKAAkKahRbiQBsAgAAAA==.',
Fu='Fujitora:BAAANQAECgQICQAAAA==.Funbunz:BAAANQAECgEIAQAAAA==.',
['Fø']='Førd:BAACNQAFFH8GAAIjAAIKEBzHCgCkAAAjAAIKEBzHCgCkAAA1AAQKfzEABCMACQriHdILAKcCACMACQoOGtILAKcCACQACAqPGHoIAAkCABEABQoqBTU6AMIAAAAA.',
Ga='Gahv:BAAANQADCggIDgAAAA==.Gahza:BAAANQADCgQIBAAAAA==.Galyte:BAAANQADCgQIBwAAAA==.Gangrene:BAABNQAECn8mAAIYAAgKHhNCTwDUAQAYAAgKHhNCTwDUAQAAAA==.Gaspasser:BAAANQAECgUIDQAAAA==.Gaviin:BAABNQAECn8eAAIWAAgKlh04GgCnAgAWAAgKlh04GgCnAgAAAA==.Gazamiseh:BAAANQABCgIIAgAAAA==.',
Ge='Gearador:BAAANQADCgMIBAAAAA==.Genovia:BAAANQADCgQIBAABNQAECggIBAAEAAAAAA==.Gerhart:BAABNQAECn8tAAMGAAkKQR5KEwABAwAGAAkKXx1KEwABAwAMAAgKhRrfCQA+AgAAAA==.',
Gi='Gigarius:BAABNQAECn8hAAIlAAYKaiGWFwA7AgAlAAYKaiGWFwA7AgAAAA==.Gizelia:BAAANQADCgMIBAAAAA==.',
Gl='Gleya:BAAANQADCgYIBwAAAA==.Gloomy:BAAANQADCgYIBgAAAA==.',
Gn='Gnomestomper:BAAANQABCgIIAQAAAA==.',
Go='Goblinsrhot:BAAANQADCggIGQAAAA==.Goncor:BAAANQAFFAEIAQAAAA==.Gorrelord:BAAANQADCgIIAgABNQAFFAUIDwAKAEMPAA==.',
Gr='Gracze:BAAANQAECgUIBQAAAA==.Gramadingg:BAAANQADCgEIAQAAAA==.Granolah:BAAANQAECgQIDwABNQAECgkJNAAWAMshAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgUIDAAAAA==.Greyback:BAAANQADCgMIAwAAAA==.Griffmonk:BAABNQAECn8kAAIHAAgK1R5VDAC7AgAHAAgK1R5VDAC7AgAAAA==.Grimoire:BAAANQAECgQIBAABNQAECgUIBgAEAAAAAA==.Grumpymage:BAABNQAECn8nAAIJAAgK9SBRBADoAgAJAAgK9SBRBADoAgAAAA==.',
Gu='Gunjamomma:BAAANQAECgMIAwAAAA==.',
Ha='Hafsac:BAAANQAECgYIDgAAAA==.Hamasakura:BAAANQADCggIDwAAAA==.Hardord:BAAANQAECgUICwAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAABNQAECn8mAAILAAgKFBqsDwAsAgALAAgKFBqsDwAsAgAAAA==.',
He='Healchucky:BAAANQAECgIIAgAAAA==.Healzjoogewd:BAAANQAECgQIBAAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.Hexflex:BAAANQAECgEIAQAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAABNQAECn8iAAINAAgKnBHcawDWAQANAAgKnBHcawDWAQAAAA==.Holikow:BAAANQAECgYIEAAAAA==.Holyherpies:BAAANQAECgIIAgAAAA==.Holyness:BAABNQAECn8XAAIlAAYK2h6SGwAOAgAlAAYK2h6SGwAOAgAAAA==.Honeybunz:BAAANQADCgMIBAAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAABNQAECn8aAAMlAAgK4xKYJgCmAQAlAAgKoBKYJgCmAQAFAAcKQAwe5wBHAQABNQAFFAQICwARANAdAA==.',
Hu='Hurano:BAAANQAECgcIEAAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Ic='Icekel:BAAANQADCgUIBQAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
Ih='Ihsan:BAAANQAECggIDQAAAA==.',
Il='Ilharess:BAAANQADCggICAAAAA==.Illusiõn:BAAANQAECgQIBAAAAA==.',
In='Inducktive:BAAANQAECgEIAQABNQAECggIGgAWAEcfAA==.Inkdot:BAABNQAECn8sAAMfAAkKnh83FQAqAwAfAAkKnh83FQAqAwAFAAgKTxWnngDgAQAAAA==.Inkshield:BAAANQADCgYICAABNQAECggIGAAHAOodAA==.Inkwell:BAAANQAECgMIAgABNQAECgkJLAAfAJ4fAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Io='Io:BAAANQAECgUIBQABNQAECgkJHQAXAFgjAA==.Iomedáe:BAAANQADCgMIAwAAAA==.',
Ir='Irishnight:BAAANQADCgQICgABNQAECgkJJwAmAKQRAA==.Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQAECgEIAQAAAA==.',
Ja='Jakobo:BAAANQAECggIEgAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarkus:BAAANQADCgYIBwAAAA==.Jarthas:BAAANQADCgYIDQAAAA==.Jazlynel:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAACNQAFFH8VAAIfAAcK6hIzBABAAgAfAAcK6hIzBABAAgA1AAQKfygAAx8ACQoiIVEOAFYDAB8ACQoiIVEOAFYDAAUAAwrMGr8sAdAAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.Jenni:BAAANQADCgcIBwAAAA==.',
Ji='Jimbostein:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyblaze:BAAANQADCgIIAgAAAA==.Jozalin:BAAANQADCgQIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgMIBwAAAA==.Junknthtrunk:BAAANQAECgIIAgAAAA==.',
Ka='Kaelana:BAAANQABCgQIBQAAAA==.Kamahl:BAABNQAECn8cAAIZAAgKqxKdigD9AQAZAAgKqxKdigD9AQAAAA==.',
Ke='Keanew:BAABNQAECn8gAAMGAAYK9BWeRACbAQAGAAYK9BWeRACbAQAMAAEKAAD+MgAtAAAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIIgAAAA==.Keonna:BAAANQADCgYIEwAAAA==.Keppra:BAAANQAECgQIBQAAAA==.Kerlin:BAABNQAECn8gAAInAAkKTRmwEgC2AgAnAAkKTRmwEgC2AgAAAA==.',
Kh='Kheilah:BAAANQADCgEIAQAAAA==.Khurst:BAAANQAECgQIBAAAAA==.',
Ki='Kialis:BAEANQAECgMIAwABNQAECgcIDAAEAAAAAA==.Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgMIBAAAAA==.Kinoxo:BAACNQAFFH8VAAIZAAcKSxw5BACQAgAZAAcKSxw5BACQAgA1AAQKfzEAAxkACQqtJMwRAHQDABkACQqtJMwRAHQDABAAAQpIIc0qAFgAAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kitsunë:BAAANQADCgYIBgAAAA==.Kittyclysm:BAAANQAECgIIAgAAAA==.',
Ko='Kossuth:BAAANQABCgEIAQAAAA==.Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQADCgYICgAAAA==.Krampusnacht:BAAANQADCgYIBgAAAA==.Krissycat:BAAANQAECgcIBwAAAA==.',
La='Langris:BAAANQAECgEIAQABNQAECgUIBgAEAAAAAA==.Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgYIDgABNQAFFAIIBgAZAM8VAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAABNQAECn8rAAINAAkKPh74GAAQAwANAAkKPh74GAAQAwAAAA==.Leiche:BAAANQAECgIIBQAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Lichma:BAAANQABCgEIAQAAAA==.Liferia:BAAANQAECgYICAABNQAECgcIDAAEAAAAAA==.Ligerzero:BAAANQAECgEIAQAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgMIBAAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECgYIGgACABwSAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Littlefry:BAAANQABCgEIAQAAAA==.Livesey:BAAANQAECgYIEAAAAA==.',
Lo='Lockpie:BAAANQADCgQIBAAAAA==.Longshañk:BAABNQAECn8bAAIoAAkKRRZABACmAgAoAAkKRRZABACmAgAAAA==.',
Lu='Lucibrew:BAABNQAECn8cAAMBAAkKkR7hEwC1AgABAAkKQxzhEwC1AgAdAAcK1h4JDABDAgAAAA==.Lunaar:BAAANQADCgUIBQAAAA==.Luto:BAAANQAECggIDAAAAA==.Luuko:BAAANQADCgMIAwAAAA==.',
Ma='Mackaveli:BAAANQADCgYIBgAAAA==.Macpreizy:BAAANQADCgQIFQAAAA==.Mattydruid:BAAANQAECgMICgAAAA==.Mavramune:BAABNQAECn8nAAISAAkK1BgfUgB3AgASAAkK1BgfUgB3AgAAAA==.',
Mc='Mcfizzertz:BAAANQAECggIBAAAAA==.Mcfürry:BAAANQAECgQIBAAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECgkJLAAVADwfAA==.Mendinna:BAAANQADCggIHQABNQAECgUIEQAEAAAAAA==.Mendool:BAAANQADCgcIBwABNQAECgUIEQAEAAAAAA==.Mendoon:BAAANQAECgUIEQAAAA==.Methir:BAAANQAECgUIBQABNQAECgcIIwAEAAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAACNQAFFH8VAAISAAYKtBfTBAAHAgASAAYKtBfTBAAHAgA1AAQKfzUAAhIACQrfJWQDANADABIACQrfJWQDANADAAAA.Mistborn:BAAANQAECggICQABNQAECggIGAAHAOodAA==.',
Mo='Moistmaker:BAAANQAECgQIBQAAAA==.Moneygame:BAABNQAECn8XAAIKAAgKUBUZmgBMAgAKAAgKUBUZmgBMAgABNQAECggIOAAGAIslAA==.Montebrew:BAAANQADCgYIBgABNQADCgcIDAAEAAAAAA==.Montecane:BAAANQADCgcIDAAAAA==.Mooferrigno:BAAANQAFFAIIAgAAAA==.Mooky:BAABNQAECn8gAAIIAAgKvAkyUACYAQAIAAgKvAkyUACYAQAAAA==.Moonfire:BAAANQAECggJCAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.Moshicat:BAAANQAECgYICwAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAABNQAECn8WAAMiAAYKIRMLEABKAQAiAAUKIRMLEABKAQAUAAQKwQqk9ADcAAAAAA==.Mythallas:BAAANQADCgIIAgAAAA==.',
Na='Nadezda:BAAANQADCggICAAAAA==.Nakir:BAAANQAECgQIDgAAAA==.Naraku:BAABNQAECn81AAMTAAkK4x+DIgBcAQAUAAcK5xzQWQBGAgATAAQKUSKDIgBcAQAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAABNQAECn8gAAIUAAgKkBMPbAAVAgAUAAgKkBMPbAAVAgAAAA==.Nehemez:BAAANQADCggICAABNQAECgEIAQAEAAAAAA==.Neshock:BAAANQAECgIIAgABNQAECggIEwAEAAAAAA==.Nettie:BAAANQAECgUIDgAAAA==.Netty:BAAANQAECgQIBgABNQAECgUIDgAEAAAAAA==.',
No='Noctyra:BAAANQADCgUICAAAAA==.Novakayne:BAAANQADCgMIBAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.Nusy:BAAANQADCgQIBAAAAA==.',
Ny='Nymphetamine:BAABNQAECn8aAAINAAcKDBRsdAC6AQANAAcKDBRsdAC6AQAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAABNQAECn8sAAIeAAkKiRCLJQAdAgAeAAkKiRCLJQAdAgAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgcIGwAeAOULAA==.',
Ow='Owenwilson:BAAANQAECgEIAQAAAA==.',
Pa='Pandaloco:BAAANQAECgMIAwAAAA==.Pandalôc:BAAANQAECgUIDgAAAA==.Pandoe:BAACNQAFFH8bAAImAAYKISNmAABiAgAmAAYKISNmAABiAgA1AAQKfzQAAiYACQqvJoMAAPkDACYACQqvJoMAAPkDAAAA.',
Pe='Penelopea:BAABNQAECn8WAAMJAAcK1RDCHAAFAQAKAAcKnwo+BwF9AQAJAAQKPhfCHAAFAQAAAA==.Perun:BAAANQAECgYIEQAAAA==.',
Ph='Phaithfulnes:BAAANQADCgUIBQABNQAECgYIFwAlANoeAA==.Phenomenal:BAABNQAECn8WAAIeAAcKGxzBJQAbAgAeAAcKGxzBJQAbAgAAAA==.Pheonyx:BAAANQAECgMIAgAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgYICwAAAA==.',
Pl='Planb:BAAANQAECgUJCwABNQAECgkJRgAUADwVAA==.',
Pn='Pneumonya:BAAANQAECgMIAwAAAA==.',
Po='Porteagarder:BAAANQAECgYICgABNQAECgcIEAAEAAAAAA==.',
Pr='Preparedpie:BAACNQAFFH8UAAMGAAYKZg84BwDFAQAGAAYK0Q44BwDFAQAaAAQKRAzoCgAZAQA1AAQKfz0AAwYACQppIh4NAD0DAAYACAq2Ih4NAD0DABoACQqfIPgKACsDAAAA.Priarace:BAAANQAECgQIBQABNQAECgcICAAEAAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAcIFwALADMWAA==.Producktive:BAAANQAECgIIAgABNQAECggIGgAWAEcfAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQAECgQIBAABNQAECgcIJQAjAOkKAA==.Príestly:BAAANQAECgYIDAAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgQIBAAAAA==.',
Py='Pyatt:BAABNQAECn8lAAIiAAgKVhnGBQBbAgAiAAgKVhnGBQBbAgAAAA==.Pyromaniacal:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändaloc:BAAANQAECgEIAQAAAA==.',
Qe='Qe:BAAANQADCgQIBAAAAA==.',
Qu='Quack:BAAANQAECggIDAAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECggIDAAEAAAAAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCggILQABNQAECgcIEAAEAAAAAA==.',
Qy='Qyburn:BAABNQAECn8ZAAMWAAkKbx22FwC6AgAWAAkKbx22FwC6AgAPAAMKixq6PADMAAAAAA==.',
Ra='Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQADCgcJBwABNQAECgUIEwAEAAAAAA==.Ragecage:BAAANQAECgIIAgABNQAECgkJHQAUAIQXAA==.Ragga:BAAANQADCgUIBQAAAA==.Randivh:BAAANQADCgYIDAAAAA==.Rassputin:BAAANQAECgYIEwAAAA==.Raye:BAAANQADCgYIBgAAAA==.',
Re='Recipes:BAABNQAECn8YAAIHAAgK6h00DQCtAgAHAAgK6h00DQCtAgAAAA==.Redbeardd:BAAANQADCggIFwAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgABNQAECgYIDgAEAAAAAA==.Rendezvous:BAAANQAECgEIAQAAAA==.Renkà:BAABNQAECn8sAAIDAAkKkBsOKwDQAgADAAkKkBsOKwDQAgAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECn8vAAIYAAkKMR/vGwDjAgAYAAkKMR/vGwDjAgAAAA==.Reyanne:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.',
Rh='Rheas:BAAANQADCgYIDAABNQAECggIBAAEAAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAcIFwALADMWAA==.',
Rn='Rn:BAAANQADCgQIBAAAAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEJAQABNQAECggIBAAEAAAAAA==.Roflthump:BAAANQADCgcJBwAAAA==.Roketraccoon:BAAANQAECgIIAgAAAA==.Rootbreaker:BAAANQAECgEIAQABNQAECgUIBgAEAAAAAA==.Rosamyna:BAEANQADCgQIBwABNQAECgUIEwAEAAAAAA==.Roshamandes:BAABNQAECn8mAAIMAAgKHhorCgA3AgAMAAgKHhorCgA3AgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgcIHgAXAJUGAA==.Runep:BAAANQAECgEIAQAAAA==.Runstupid:BAAANQADCgEIAQAAAA==.',
['Rè']='Rèi:BAAANQAECgMIBgABNQAECggILQASANIiAA==.',
Sa='Sabermage:BAAANQAECgYICQAAAA==.Sacredchikín:BAABNQAECn8hAAMUAAkKlhymKgDXAgAUAAkKlhymKgDXAgATAAEKuBSYdQA4AAAAAA==.Samuel:BAAANQAECgIIBQAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgQICAAAAA==.Saxa:BAABNQAECn8pAAIaAAgK1SIDCwArAwAaAAgK1SIDCwArAwAAAA==.',
Sc='Screamsoda:BAAANQAECgUICQABNQAECggIGAAHAOodAA==.Scrubzz:BAAANQAECgUJCwAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekobrew:BAAANQADCgYICQAAAA==.Seyekolock:BAAANQAECgQIDgAAAA==.Seyekosis:BAABNQAECn8aAAIaAAcKZBtBJQAYAgAaAAcKZBtBJQAYAgAAAA==.',
Sg='Sgathaich:BAEANQAECgUIBwABNQAECgYIBwAEAAAAAA==.',
Sh='Shadowzform:BAAANQABCgYIBAABNQAECgUICAAEAAAAAA==.Shallistiah:BAABNQAECn8iAAMIAAgKnwzuTACqAQAIAAgKnwzuTACqAQAnAAYKwQxtQgARAQAAAA==.Shamadin:BAAANQAECgMIAwAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdh:BAAANQAECgYIDAAAAA==.Shamdwarf:BAAANQAECgQIBAAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQADCggIDgAAAA==.Shobadon:BAAANQAECggICgAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgUICAAAAA==.',
Si='Siatral:BAACNQAFFH8LAAIRAAQK0B3vFgBXAAARAAQK0B3vFgBXAAA1AAQKfysAAxEACQoZI9gEAGADABEACQoZI9gEAGADACQAAQruEtEiADoAAAAA.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQAECgMIBAABNQAECggIBAAEAAAAAA==.Sigvolden:BAAANQAECgEJAQABNQAECggIBAAEAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAABNQAECn8jAAMJAAgKHhh+BwB2AgAJAAgKHhh+BwB2AgAKAAYKwQKIUwEBAQAAAA==.Silver:BAAANQAECgIIAgABNQAECggIIwAJAB4YAA==.Siona:BAABNQAECn8mAAISAAgKQAiIpgC0AQASAAgKQAiIpgC0AQAAAA==.Sixpaths:BAAANQAECgYIEwABNQAECggIGAAHAOodAA==.Siyunkai:BAEANQAECgIIAwABNQAECgQIBAAEAAAAAA==.Siyunprai:BAEANQAECgQIBAAAAA==.Siyunzu:BAEANQAECgIIAgABNQAECgQIBAAEAAAAAA==.',
Sk='Skadie:BAABNQAECn8nAAISAAgKqBXrYgBNAgASAAgKqBXrYgBNAgAAAA==.Skittellz:BAAANQABCgMIAwAAAA==.Skiye:BAAANQADCgcIBwAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgAEAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgAEAAAAAA==.Skwup:BAABNQAECn8pAAMfAAkKRBoFLgCsAgAfAAkKRBoFLgCsAgAFAAQKpxZgFgHzAAAAAA==.',
Sl='Slackness:BAAANQAECgEIAQAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slappygilmor:BAAANQADCgcIBwABNQAECgQIBAAEAAAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggJCQABNQAFFAUIDwAKAEMPAA==.Sleepybeard:BAAANQAECgQICAAAAA==.Slubadub:BAABNQAECn8aAAQMAAkKmx3gDADyAQAaAAgKThsjHwBUAgAMAAUKySLgDADyAQAGAAUKHhM8VQAzAQABNQAFFAIIAgAEAAAAAA==.',
Sm='Smiteslay:BAAANQAECgUJCgABNQAFFAUIDwAKAEMPAA==.',
Sn='Snivels:BAAANQAECgcIEQAAAA==.Snïpe:BAAANQABCgQIBAAAAA==.',
So='So:BAAANQAECgUIDgAAAA==.Soggycat:BAEANQADCgEIAQAAAA==.Soil:BAABNQAECn8lAAIiAAkKwCH6AABrAwAiAAkKwCH6AABrAwAAAA==.Somna:BAAANQAECgUJCwAAAA==.',
Sp='Sparrkle:BAABNQAECn8nAAITAAkKhQXaHgB3AQATAAkKhQXaHgB3AQAAAA==.Spayme:BAAANQAECgEIAQAAAA==.Spinecrawler:BAABNQAECn8dAAIUAAkKhBdASgBxAgAUAAkKhBdASgBxAgAAAA==.Spyro:BAAANQAECgIIAwAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgMIBAAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stickshamm:BAAANQAECgEIAQAAAA==.Stiick:BAABNQAECn8mAAIlAAgKIxr+GQAgAgAlAAgKIxr+GQAgAgAAAA==.Stonecracker:BAAANQADCgMIBAAAAA==.Stìmpak:BAAANQADCgYIDwABNQAECgUIBgAEAAAAAA==.Stöut:BAAANQAECgIIAgABNQAECgUIBgAEAAAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.Sudsy:BAAANQADCgUICAABNQAECgcIGAAQABMcAA==.Supadupaman:BAAANQAECggIDwAAAA==.Supaman:BAAANQABCgUIBwAAAA==.',
Sw='Sweetbippy:BAAANQAECgUIDgAAAA==.Swifthealss:BAABNQAECn8YAAImAAYKehPgJQBhAQAmAAYKehPgJQBhAQAAAA==.Swirls:BAAANQAECgIIAgAAAA==.',
Sy='Sylunae:BAAANQADCggIIQABNQAECgcIEAAEAAAAAA==.Syluné:BAAANQAECgcIEAAAAA==.',
Ta='Tabasco:BAAANQAECgcIBwABNQAFFAcIFwALADMWAA==.Tacoshaman:BAAANQADCgIJAgABNQAECgMIAwAEAAAAAA==.Tacozpriest:BAAANQAECgIIAgABNQAECgMIAwAEAAAAAA==.Taelyx:BAAANQAECgYIEwAAAA==.Tamago:BAAANQAECgYIBgABNQAFFAcIFQAfAOoSAA==.Tambot:BAAANQAECgYICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgYIEQAAAA==.Tazmina:BAABNQAECn8hAAIGAAYKwB7LQQCtAQAGAAYKwB7LQQCtAQAAAA==.',
Te='Teddykgb:BAAANQAECgIIAwAAAA==.Teenieweenie:BAAANQADCgUIBQAAAA==.Tequilàrose:BAAANQADCgYIBwABNQAECgQIBAAEAAAAAA==.Tessa:BAABNQAECn8mAAIDAAgKtBR3WAAXAgADAAgKtBR3WAAXAgAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAABNQAECn8lAAQNAAkKYR15MACjAgANAAgKnR55MACjAgAOAAgKWhJdIQApAgAgAAEKvQmKLAAqAAAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.Thejudge:BAAANQAECgcIBwABNQAFFAIIAgAEAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinkey:BAAANQAECgMIAwAAAA==.Tinyjapeto:BAAANQAECgQICgAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAABNQAECn8mAAISAAgKIiIGLgDhAgASAAgKIiIGLgDhAgAAAA==.Tortapounder:BAAANQAECgQICQAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgUICwAAAA==.',
Tu='Turin:BAABNQAECn8nAAILAAkK3gkYGACpAQALAAkK3gkYGACpAQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twiggysmalls:BAAANQADCgUIBAAAAA==.Twilghtdawn:BAAANQADCgUIBQAAAA==.Twotone:BAAANQAECggICAAAAA==.',
Ty='Tybo:BAABNQAECn8UAAIVAAYKcR8dFAAjAgAVAAYKcR8dFAAjAgAAAA==.Tycho:BAAANQADCgYIDQAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.Tydros:BAAANQADCggICAAAAA==.Tyriondale:BAAANQADCgEIAQAAAA==.',
Un='Uncás:BAABNQAECn8bAAISAAYKEQxiugCKAQASAAYKEQxiugCKAQAAAA==.Undyinggnome:BAAANQAECgQIBAAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Ur='Urza:BAAANQADCgQIBAAAAA==.',
Va='Vaelock:BAABNQAECn8ZAAQUAAcK1Q2wpACGAQAUAAcKyA2wpACGAQAiAAIKWBP9IwBeAAATAAIKTAPKdQA3AAAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQAECgQIBAAAAA==.Valoryan:BAABNQAECn8mAAInAAgKYBqUGwBWAgAnAAgKYBqUGwBWAgAAAA==.Valy:BAAANQADCgcIBwAAAA==.Valyteilssra:BAAANQAECgQIBAAAAA==.Vasoline:BAAANQAECggICAABNQAECgkJGQAXACMhAA==.Vaxtur:BAAANQAECggJCAAAAA==.',
Ve='Vegà:BAABNQAECn8jAAMdAAYKzQ/9GQBBAQAdAAYKzQ/9GQBBAQABAAQKOgsKVQCSAAAAAA==.Vendettis:BAAANQAECgEIAQAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYJBgABNQAECgUIBwAEAAAAAA==.Veylyn:BAABNQAECn8cAAIFAAYKFggb/gAcAQAFAAYKFggb/gAcAQAAAA==.Veztaroth:BAABNQAECn8eAAIYAAcKuQ9aXgCSAQAYAAcKuQ9aXgCSAQAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQAECgIIAgAAAA==.Voidyo:BAABNQAECn8wAAMaAAkK1STwAgCqAwAaAAkK1STwAgCqAwAGAAgKYR4pHwCdAgAAAA==.',
['Vë']='Vëngeåncelöt:BAAANQADCgQIBAAAAA==.',
Wa='War:BAAANQADCggICAABNQAECggIGQAcAKQPAA==.',
We='Weißenacht:BAAANQADCgcIBwAAAA==.',
Wh='Whiskeyjak:BAABNQAECn8jAAMLAAgKcx0vCwCIAgALAAgKcx0vCwCIAgAZAAgKMwt4qgCuAQAAAA==.Whycatihealu:BAAANQADCgQICAAAAA==.',
Wi='Willowbark:BAAANQADCgYIEwAAAA==.Willowest:BAABNQAECn85AAISAAkKGSLNDwBkAwASAAkKGSLNDwBkAwAAAA==.Wizbizzler:BAAANQAECgYJDgAAAA==.',
Wr='Wrathstorm:BAABNQAECn8sAAIVAAkKPB+dBABHAwAVAAkKPB+dBABHAwAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanier:BAAANQADCgYIGAABNQAECgcIGQAiACgQAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQAECgYIEAAAAA==.Xithia:BAEANQAECgcIDAAAAA==.',
Xo='Xorm:BAAANQAECggICAAAAA==.',
Xx='Xxcor:BAAANQAECgEIAQAAAA==.',
Xy='Xyndylyne:BAAANQADCgcIBwAAAA==.',
Ya='Yahtze:BAAANQADCgYIBgAAAA==.Yanella:BAABNQAECn8iAAINAAkK+hcENQCRAgANAAkK+hcENQCRAgAAAA==.',
Yi='Yisdk:BAAANQAECgUICQAAAA==.Yispally:BAAANQAECgMIAwAAAA==.Yisshaman:BAAANQAECgcIEQAAAA==.',
Yo='Yogibearz:BAAANQAECgEIAQABNQAECgQICQAEAAAAAA==.',
Yu='Yunbao:BAAANQAECgEIAQAAAA==.',
Za='Zaijr:BAAANQAECgMIAwAAAA==.Zanax:BAAANQAECgUIDgAAAA==.Zandarbribbs:BAAANQAECgIIAwAAAA==.Zarrah:BAAANQABCgYICgAAAA==.',
Ze='Zennya:BAABNQAECn8dAAInAAgKCh/eEwCpAgAnAAgKCh/eEwCpAgAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.',
Zo='Zoldyck:BAAANQADCggIIgAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zyrx:BAAANQADCggIDwAAAA==.',
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
